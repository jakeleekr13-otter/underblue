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
/// Nothing is saved between photos. A new photo starts in Auto.
///
/// - Auto: the automatic mask applies. The overlay is hidden and the picks stay in memory.
/// - Manual: the picks apply. The first time, the picks are what Auto would use, so the picture does not change
///   until the user taps. Reset is the only action that clears the picks.
struct SubjectSelection {
    enum Mode: Equatable, Sendable { case auto, manual }
    /// `none` means Vision found no usable subject for this photo. `waitingForModel` means the precise
    /// model is still downloading; the picker opens by itself when it is ready.
    enum Status: Equatable, Sendable { case idle, detecting, waitingForModel, none, ready }
    /// Why the last tap did nothing, for a message next to the picker.
    enum Notice: Equatable, Sendable { case tooMuch, tooLarge }

    private(set) var mode = Mode.auto
    private(set) var status = Status.idle
    private(set) var picks: Set<Int> = []
    /// False after Done. The mode stays Manual and the picks stay applied.
    private(set) var overlayVisible = false
    private(set) var candidates: SubjectCandidates?
    /// Tier two and three regions, shown with the picker but not picked. Nil when none was found.
    private(set) var tiers: SubjectTiers?
    /// The tier lines with the picked groups taken out. Rebuilt when the picks or the tiers change.
    private(set) var tierDrawing: SubjectTiers.Drawing?
    private(set) var notice: Notice?
    /// What preview and export receive. Rebuilt on every change, not on every read.
    private(set) var choice = SubjectChoice.auto

    /// Changes whenever the rendered result can change. A view task can wait on it.
    struct Key: Hashable, Sendable { let manual: Bool; let picks: Set<Int> }
    var key: Key { Key(manual: mode == .manual, picks: picks) }

    var isManual: Bool { mode == .manual }
    /// The overlay shows in Manual mode, until the user presses Done.
    var showsOverlay: Bool { mode == .manual && overlayVisible && candidates != nil }
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
        mode = .manual
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

    /// Manual again with the candidates already known. Needs no detection.
    mutating func resumeManual() {
        guard candidates != nil else { return }
        mode = .manual; overlayVisible = true; notice = nil; rebuild()
    }

    mutating func setTiers(_ found: SubjectTiers?) { tiers = found; redraw() }

    mutating func done() { overlayVisible = false }
    mutating func edit() { if mode == .manual { overlayVisible = true } }

    mutating func reset() {
        guard let candidates else { return }
        picks = Self.autoPicks(candidates); notice = nil; rebuild()
    }

    /// A tap on a group. Adding a group is refused when the picks would cover too much of the frame.
    mutating func toggle(_ id: Int) {
        guard mode == .manual, let candidates, let group = candidates.group(id) else { return }
        if picks.contains(id) {
            picks.remove(id); notice = nil
        } else if candidates.accepts(id, adding: picks) {
            picks.insert(id); notice = nil
        } else {
            notice = group.share > SubjectCandidates.maximumPickedShare ? .tooLarge : .tooMuch
        }
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

    private mutating func rebuild() {
        redraw()
        guard mode == .manual, let candidates else { choice = .auto; return }
        choice = .picked(candidates.mask(picking: picks))
    }

    private mutating func redraw() {
        tierDrawing = tiers?.drawing(excluding: candidates?.mask(picking: picks))
    }
}
