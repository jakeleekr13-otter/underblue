import Foundation

/// Whether the manual subject picker is offered. One value for the whole device, off by default.
/// Off: the Auto/Manual bar is hidden and every photo uses Auto.
///
/// The picker needs iOS 27 or macOS 27 (Jake, 24 Oct 2026). The subject search on 26 was not good enough
/// for manual picking. 27 adds the precise mask (SubjectMask.estimatePrecise). Below 27 the switch shows
/// in Help but stays off and locked, and a saved "on" from another device is ignored.
struct SubjectPickerStore {
    static let key = "subjectPicker.enabled"
    static var isSupported: Bool {
        if #available(iOS 27, macOS 27, *) { return true }
        return false
    }
    private let defaults: UserDefaults
    private let supported: Bool
    init(defaults: UserDefaults = .standard, supported: Bool = SubjectPickerStore.isSupported) {
        self.defaults = defaults
        self.supported = supported
    }
    func load() -> Bool { supported && defaults.bool(forKey: Self.key) }
    func save(_ enabled: Bool) { defaults.set(enabled, forKey: Self.key) }
}

/// The subject picker state of one photo: iPhone keeps one in `EditorModel`, Mac one per queue item.
/// Nothing is saved between photos. A new photo starts in Auto, at subject strength 100%.
///
/// - Auto: the automatic mask applies. The overlay is hidden and the picks stay in memory.
/// - Semi-auto: the picks among the groups Vision found apply. The first time, the picks are what Auto would
///   use, so the picture does not change until the user taps. Reset is the only action that clears the picks.
/// - Manual: the user presses and holds on any subject (docs/ManualSubject.md). Each press adds one precise
///   mask; a press on a picked subject removes it. Reset clears the presses.
///
/// Semi-auto and Manual have a subject strength (Jake, 25 Oct 2026). Auto stays at 100%.
struct SubjectSelection {
    enum Mode: Equatable, Sendable { case auto, semiAuto, manual }
    /// `none` means Vision found no usable subject for this photo. `waitingForModel` means the precise
    /// model is still downloading; the picker opens by itself when it is ready.
    enum Status: Equatable, Sendable { case idle, detecting, waitingForModel, none, ready }
    /// Why the last tap did nothing, for a message next to the picker.
    enum Notice: Equatable, Sendable { case tooMuch, tooLarge, nothingFound }

    private(set) var mode = Mode.auto
    private(set) var status = Status.idle
    private(set) var picks: Set<Int> = []
    /// Tier pieces the user turned off (SubjectTiers.pieces). Every piece starts on.
    private(set) var tiersOff: Set<Int> = []
    /// False after Done. The mode stays Manual and the picks stay applied.
    private(set) var overlayVisible = false
    private(set) var candidates: SubjectCandidates?
    /// Tier two and three regions, shown with the picker but not picked. Nil when none was found.
    private(set) var tiers: SubjectTiers?
    /// The tier lines with the picked groups taken out. Rebuilt when the picks or the tiers change.
    private(set) var tierDrawing: SubjectTiers.Drawing?
    /// The tappable tier pieces, outside every group. Rebuilt when the groups or the tiers change.
    private(set) var tierPieces: SubjectTiers.Pieces?
    private(set) var notice: Notice?
    /// Manual's presses, one precise mask each, in press order.
    private(set) var presses: [SubjectMask] = []
    /// The presses as groups, for the outline and the hit test. Nil with no press.
    private(set) var pressed: SubjectCandidates?
    /// Where a press is being segmented, 0...1 from the top left. The picker draws a ring there.
    private(set) var pressing: CGPoint?
    /// Counts press changes, so `key` changes when a press is added or removed.
    private var pressVersion = 0
    /// The subject strength slider, 0 to `maximumStrength`. 1 is the lift as Auto applies it.
    private(set) var strength: Float = 1
    static let maximumStrength: Float = 1.5
    /// What preview and export receive. Rebuilt on every change, not on every read.
    private(set) var choice = SubjectChoice.auto

    /// Changes whenever the rendered result can change. A view task can wait on it.
    struct Key: Hashable, Sendable {
        let mode: Mode; let picks: Set<Int>; let tiersOff: Set<Int>; let presses: Int; let strength: Float
    }
    var key: Key { Key(mode: mode, picks: picks, tiersOff: tiersOff, presses: pressVersion, strength: strength) }

    var isSemiAuto: Bool { mode == .semiAuto }
    var isManual: Bool { mode == .manual }
    /// Semi-auto shows the groups, Manual the presses, until the user presses Done.
    var showsOverlay: Bool {
        switch mode {
        case .auto: false
        case .semiAuto: overlayVisible && candidates != nil
        case .manual: overlayVisible
        }
    }
    /// The strength slider shows in Semi-auto and Manual once something is picked.
    var showsStrength: Bool {
        switch mode {
        case .auto: false
        case .semiAuto: !picks.isEmpty
        case .manual: !presses.isEmpty
        }
    }
    var isDetecting: Bool { status == .detecting }

    // MARK: Changes

    mutating func startDetecting() { status = .detecting; notice = nil }

    /// Detection finished. Nil candidates mean no subject: the photo stays in Auto and the screen says so.
    mutating func finishDetecting(_ found: SubjectCandidates?) {
        guard let found, !found.isEmpty else {
            candidates = nil; status = .none; mode = .auto; overlayVisible = false; choice = .auto
            return
        }
        if candidates == nil { picks = Self.autoPicks(found) }
        candidates = found
        status = .ready
        mode = .semiAuto
        overlayVisible = true
        notice = nil
        rebuild()
    }

    /// The precise model is not ready. The photo stays in Auto until it is.
    mutating func waitForModel() { status = .waitingForModel; mode = .auto; overlayVisible = false; choice = .auto }

    /// Back to the automatic mask. The picks stay, so Manual returns to them.
    mutating func useAuto() {
        mode = .auto; overlayVisible = false; notice = nil; choice = .auto
        if status == .detecting { status = candidates == nil ? .idle : .ready }
    }

    /// Semi-auto again with the candidates already known. Needs no detection.
    mutating func resumeSemiAuto() {
        guard candidates != nil else { return }
        mode = .semiAuto; overlayVisible = true; notice = nil; rebuild()
    }

    /// Manual: the presses so far apply, and the overlay waits for the next press. Needs no detection.
    mutating func useManual() {
        if status == .detecting || status == .waitingForModel { status = candidates == nil ? .idle : .ready }
        mode = .manual; overlayVisible = true; notice = nil; rebuild()
    }

    // MARK: Manual presses

    /// The press that covers a point, to remove it. Nil when the point is on no picked subject.
    func press(at point: CGPoint) -> Int? { pressed?.groupMask(at: point) }

    mutating func startPress(at point: CGPoint) { pressing = point; notice = nil }

    /// A press finished. Nil means the model found nothing there. A mask that would push the picks past
    /// `SubjectCandidates.maximumPickedShare` is refused, as a Semi-auto tap is.
    mutating func finishPress(_ mask: SubjectMask?) {
        pressing = nil
        guard mode == .manual else { return }
        guard let mask else { notice = .nothingFound; return }
        if let first = presses.first, first.width != mask.width || first.height != mask.height { return }
        let share = mask.values.reduce(0, +) / Float(mask.values.count)
        let union = Self.union(presses + [mask])
        let total = union.map { $0.values.reduce(0, +) / Float($0.values.count) } ?? share
        guard total <= SubjectCandidates.maximumPickedShare else {
            notice = share > SubjectCandidates.maximumPickedShare ? .tooLarge : .tooMuch
            return
        }
        presses.append(mask); pressVersion += 1; notice = nil
        rebuild()
    }

    /// The press stopped with no result: cancelled, or the model is not ready.
    mutating func cancelPress() { pressing = nil }

    mutating func removePress(_ index: Int) {
        guard mode == .manual, presses.indices.contains(index) else { return }
        presses.remove(at: index); pressVersion += 1; notice = nil
        rebuild()
    }

    mutating func setStrength(_ value: Float) {
        strength = min(Self.maximumStrength, max(0, value))
        rebuild()
    }

    mutating func setTiers(_ found: SubjectTiers?) {
        tiers = found
        tierPieces = candidates.flatMap { c in found?.pieces(excluding: c.mask(picking: Set(c.groups.map(\.id)))) }
            ?? found?.pieces(excluding: nil)
        redraw()
    }

    mutating func done() { overlayVisible = false }
    mutating func edit() { if mode != .auto { overlayVisible = true } }

    /// Semi-auto: back to the automatic picks, every tier piece on. Manual: no presses. Both: strength 100%.
    mutating func reset() {
        switch mode {
        case .auto: return
        case .semiAuto:
            guard let candidates else { return }
            picks = Self.autoPicks(candidates); tiersOff = []
        case .manual:
            presses = []; pressVersion += 1
        }
        strength = 1; notice = nil; rebuild()
    }

    /// A tap on a group. Adding a group is refused when the picks would cover too much of the frame.
    mutating func toggle(_ id: Int) {
        guard mode == .semiAuto, let candidates, let group = candidates.group(id) else { return }
        if picks.contains(id) {
            picks.remove(id); notice = nil
        } else if candidates.accepts(id, adding: picks) {
            picks.insert(id); notice = nil
        } else {
            notice = group.share > SubjectCandidates.maximumPickedShare ? .tooLarge : .tooMuch
        }
        rebuild()
    }

    /// A tap on a tier piece: on or off. A tier piece has no share cap, because it adds no subject.
    mutating func toggleTier(_ id: Int) {
        guard mode == .semiAuto, tierPieces?.items.contains(where: { $0.id == id }) == true else { return }
        if tiersOff.contains(id) { tiersOff.remove(id) } else { tiersOff.insert(id) }
        notice = nil
        rebuild()
    }

    // MARK: Derived

    var pickedCount: Int { picks.count }
    var groupCount: Int { candidates?.groups.count ?? 0 }

    /// What Auto would protect: every group, or none when the whole is outside the lift's limits.
    /// This is the test of PhotoProcessor's auto lift mask, so Manual starts where Auto is.
    static func autoPicks(_ candidates: SubjectCandidates) -> Set<Int> {
        let total = candidates.groups.reduce(0) { $0 + $1.share }
        guard total >= SubjectMask.minimumShare, total <= SubjectMask.liftMaximumShare else { return [] }
        return Set(candidates.groups.map(\.id))
    }

    /// The masks as one: the largest value at each cell. Nil for none.
    static func union(_ masks: [SubjectMask]) -> SubjectMask? {
        guard let first = masks.first else { return nil }
        var values = first.values
        for mask in masks.dropFirst() where mask.values.count == values.count {
            for i in values.indices { values[i] = max(values[i], mask.values[i]) }
        }
        return SubjectMask(width: first.width, height: first.height, values: values)
    }

    private mutating func rebuild() {
        pressed = SubjectCandidates.pressed(presses)
        redraw()
        switch mode {
        case .auto: choice = .auto
        case .semiAuto:
            guard let candidates else { choice = .auto; return }
            choice = .picked(candidates.mask(picking: picks), tiersOff: tiersOff, strength: strength)
        case .manual:
            // Every tier piece stays on, as in Auto: Manual draws no tier lines to turn them off.
            choice = .picked(Self.union(presses), strength: strength)
        }
    }

    private mutating func redraw() {
        tierDrawing = tiers?.drawing(excluding: candidates?.mask(picking: picks), off: tiersOff, pieces: tierPieces)
    }
}
