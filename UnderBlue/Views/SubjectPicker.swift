import SwiftUI

/// Maps a tap on the fitted photo to a subject group. The overlay sits inside the zoomed image, so a point
/// in its own space is already a photo point, at any zoom and aspect.
enum SubjectPickerGeometry {
    /// Smallest comfortable tap size, in points on screen.
    static let tapSize: CGFloat = 44

    /// `location` is in the fitted image's own space. The result is 0...1 with the origin at the top left.
    static func normalized(_ location: CGPoint, in size: CGSize) -> CGPoint? {
        guard size.width > 0, size.height > 0 else { return nil }
        return CGPoint(x: location.x / size.width, y: location.y / size.height)
    }

    /// Half the tap size as a share of the photo, at the current zoom. A small subject stays easy to hit.
    static func tolerance(in size: CGSize, zoom: CGFloat) -> CGFloat {
        let side = min(size.width, size.height) * max(1, zoom)
        return side > 0 ? tapSize / 2 / side : 0
    }

    static func group(at location: CGPoint, in size: CGSize, zoom: CGFloat, of candidates: SubjectCandidates) -> Int? {
        normalized(location, in: size).flatMap { candidates.group(at: $0, tolerance: tolerance(in: size, zoom: zoom)) }
    }

    enum Hit: Equatable { case group(Int), piece(Int) }

    /// What the pixels under the tap belong to: a Vision group's mask first, then a tier piece. Off every
    /// mask, the nearest mask pixel within half the tap size on screen decides, group or piece alike.
    /// Boxes never decide: a large subject's box covers the small fish around it.
    static func hit(at location: CGPoint, in size: CGSize, zoom: CGFloat, of candidates: SubjectCandidates,
                    tiers: SubjectTiers?, pieces: SubjectTiers.Pieces?) -> Hit? {
        guard size.width > 0, size.height > 0 else { return nil }
        func at(_ p: CGPoint) -> Hit? {
            let n = CGPoint(x: p.x / size.width, y: p.y / size.height)
            if let id = candidates.groupMask(at: n) { return .group(id) }
            if let tiers, let pieces, let id = tiers.pieceLabel(at: n, in: pieces) { return .piece(id) }
            return nil
        }
        if let direct = at(location) { return direct }
        // Half the tap size on screen, in the overlay's own points (the overlay zooms with the image).
        let reach = tapSize / 2 / max(1, zoom), steps = 8
        var best: (hit: Hit, distance: CGFloat)?
        for iy in -steps...steps { for ix in -steps...steps {
            let dx = CGFloat(ix) / CGFloat(steps) * reach, dy = CGFloat(iy) / CGFloat(steps) * reach
            let d = (dx * dx + dy * dy).squareRoot()
            guard d <= reach, d < (best?.distance ?? .infinity), let found = at(CGPoint(x: location.x + dx, y: location.y + dy)) else { continue }
            best = (found, d)
        } }
        return best?.hit
    }
}

/// Edge lines, fills and badges for the subject groups. Colour is not the only signal:
/// a selected group has a thick line, a check mark and a fill; a group that is not selected has
/// a thin line and an empty circle.
///
/// Tiers two and three (SubjectTiers) sit under the groups: amber for the scene in front, lavender for the
/// scene further back. Each piece has its own badge and turns on or off with a tap. A piece that is off draws
/// a thin white line and an empty circle, as a group that is not selected.
struct SubjectPicker: View {
    let candidates: SubjectCandidates
    let picks: Set<Int>
    var tiers: SubjectTiers? = nil
    var tierPieces: SubjectTiers.Pieces? = nil
    var tierDrawing: SubjectTiers.Drawing? = nil
    var tiersOff: Set<Int> = []
    /// Fitted size of the photo on screen, at zoom 1.
    let size: CGSize
    let zoom: CGFloat
    /// Manual mode (docs/ManualSubject.md): `candidates` are the presses, all picked. On the Mac a click calls
    /// `onPress` with the point, 0...1 from the top left. On the iPhone the press and hold is ZoomablePreview's
    /// `onHold`, so this view takes no touch there, and a single tap does nothing.
    var pressMode = false
    /// Where a press is being segmented, 0...1. A ring shows there.
    var pressing: CGPoint? = nil
    var onPress: (CGPoint) -> Void = { _ in }
    var onToggleTier: (Int) -> Void = { _ in }
    let onToggle: (Int) -> Void

    var body: some View {
        // Lines and badges keep their size on screen while the image zooms.
        let unit = 1 / max(1, zoom)
        ZStack(alignment: .topLeading) {
            if pressMode {
                #if os(macOS)
                Color.clear.contentShape(Rectangle())
                    .onTapGesture(count: 1, coordinateSpace: .local) { location in
                        if let point = SubjectPickerGeometry.normalized(location, in: size) { onPress(point) }
                    }
                #endif
            } else {
                Color.clear.contentShape(Rectangle())
                    .onTapGesture(count: 1, coordinateSpace: .local) { location in
                        switch SubjectPickerGeometry.hit(at: location, in: size, zoom: zoom, of: candidates, tiers: tiers, pieces: tierPieces) {
                        case .group(let id)?: onToggle(id)
                        case .piece(let id)?: onToggleTier(id)
                        case nil: break
                        }
                    }
            }
            if let tierDrawing { tierLines(tierDrawing, unit: unit) }
            ForEach(tierPieces?.items ?? []) { piece in
                pieceBadge(piece, on: !tiersOff.contains(piece.id), unit: unit)
            }
            ForEach(candidates.groups) { group in
                groupView(group, selected: picks.contains(group.id), unit: unit)
            }
            if let pressing {
                ZStack {
                    Circle().fill(Color.black.opacity(0.35))
                    Circle().stroke(Self.selectedColor, lineWidth: 3 * unit)
                    ProgressView().controlSize(.small).tint(.white)
                }
                .frame(width: 44 * unit, height: 44 * unit)
                .position(x: pressing.x * size.width, y: pressing.y * size.height)
                .allowsHitTesting(false).accessibilityHidden(true)
            }
        }
    }

    /// Selected: mint fill, thick mint line along the subject's edge, a check. Not selected: a thin white line and an empty circle.
    @ViewBuilder private func groupView(_ group: SubjectGroup, selected: Bool, unit: CGFloat) -> some View {
        let badge = 28 * unit
        ZStack(alignment: .topLeading) {
            if selected, let fill = group.fill {
                Image(decorative: fill, scale: 1).renderingMode(.template).resizable()
                    .frame(width: size.width, height: size.height).foregroundStyle(Self.selectedColor).opacity(0.3)
                    .allowsHitTesting(false)
            }
            if let line = selected ? group.thickOutline : group.thinOutline {
                Image(decorative: line, scale: 1).renderingMode(.template).resizable()
                    .frame(width: size.width, height: size.height)
                    .foregroundStyle(selected ? Self.selectedColor : Color.white).opacity(selected ? 1 : 0.7)
                    .shadow(color: .black.opacity(0.6), radius: 1.5 * unit)
                    .allowsHitTesting(false)
            }
            ZStack {
                Circle().fill(selected ? Self.selectedColor : Color.black.opacity(0.45))
                Circle().stroke(Color.white, lineWidth: 2 * unit)
                if selected { Image(systemName: "checkmark").font(.system(size: 15 * unit, weight: .bold)).foregroundStyle(.black) }
            }
            .frame(width: badge, height: badge)
            // Centred on the top of the subject. Clamped, so a subject at the photo edge keeps its badge in view.
            .offset(x: min(max(0, group.anchor.x * size.width - badge / 2), max(0, size.width - badge)),
                    y: min(max(0, group.anchor.y * size.height - badge / 2), max(0, size.height - badge)))
            .allowsHitTesting(false)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Self.label(group, position: group.id + 1, selected: selected))
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { onToggle(group.id) }
    }

    static let selectedColor = Color(red: 0.0, green: 0.9, blue: 0.65)
    static let tier2Color = Color(red: 1.0, green: 0.72, blue: 0.2)
    static let tier3Color = Color(red: 0.78, green: 0.66, blue: 1.0)

    /// On: a disc in the tier colour with a check. Off: an empty circle.
    @ViewBuilder private func pieceBadge(_ piece: SubjectTiers.Piece, on: Bool, unit: CGFloat) -> some View {
        let badge = 24 * unit
        let colour = piece.tier == 2 ? Self.tier2Color : Self.tier3Color
        ZStack {
            Circle().fill(on ? colour : Color.black.opacity(0.45))
            Circle().stroke(Color.white, lineWidth: 2 * unit)
            if on { Image(systemName: "checkmark").font(.system(size: 13 * unit, weight: .bold)).foregroundStyle(.black) }
        }
        .frame(width: badge, height: badge)
        .offset(x: min(max(0, piece.anchor.x * size.width - badge / 2), max(0, size.width - badge)),
                y: min(max(0, piece.anchor.y * size.height - badge / 2), max(0, size.height - badge)))
        .allowsHitTesting(false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(on ? String(localized: "Scene area \(piece.id + 1), on") : String(localized: "Scene area \(piece.id + 1), off"))
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { onToggleTier(piece.id) }
    }

    @ViewBuilder private func tierLines(_ tiers: SubjectTiers.Drawing, unit: CGFloat) -> some View {
        if let off = tiers.offOutline {
            Image(decorative: off, scale: 1).renderingMode(.template).resizable()
                .frame(width: size.width, height: size.height)
                .foregroundStyle(Color.white).opacity(0.7)
                .shadow(color: .black.opacity(0.6), radius: 1.5 * unit)
                .allowsHitTesting(false).accessibilityHidden(true)
        }
        ForEach(Array([(tiers.tier3Outline, Self.tier3Color), (tiers.tier2Outline, Self.tier2Color)].enumerated()), id: \.offset) { _, entry in
            if let line = entry.0 {
                Image(decorative: line, scale: 1).renderingMode(.template).resizable()
                    .frame(width: size.width, height: size.height)
                    .foregroundStyle(entry.1).opacity(0.9)
                    .shadow(color: .black.opacity(0.6), radius: 1.5 * unit)
                    .allowsHitTesting(false)
            }
        }
        .accessibilityHidden(true)
    }

    static func label(_ group: SubjectGroup, position: Int, selected: Bool) -> String {
        selected ? String(localized: "Subject group \(position), selected, \(group.instances.count) included")
            : String(localized: "Subject group \(position), not selected, \(group.instances.count) included")
    }
}

/// The text under the picker controls: what is selected, and why a tap did nothing.
@MainActor
enum SubjectPickerText {
    static func summary(_ selection: SubjectSelection) -> String {
        if selection.isManual {
            let count = selection.presses.count
            #if os(macOS)
            if count == 0 { return String(localized: "Click a subject to pick it.") }
            return String(localized: "\(count) picked. Click a subject to add it, or a picked one to remove it.")
            #else
            if count == 0 { return String(localized: "Press and hold a subject to pick it.") }
            return String(localized: "\(count) picked. Press and hold a subject to add it, or a picked one to remove it.")
            #endif
        }
        switch selection.status {
        case .detecting: return String(localized: "Looking for subjects…")
        case .waitingForModel:
            return PreciseModelLoader.shared.state == .waitingForNetwork
                ? String(localized: "Connect to the internet to download the subject model.")
                : String(localized: "Getting the subject model ready…")
        case .none: return String(localized: "No subjects found. UnderBlue uses Auto.")
        case .idle: return String(localized: "Auto protects the main subjects it finds.")
        case .ready:
            if selection.isSemiAuto {
                if selection.pickedCount == 0 { return String(localized: "No subject selected. Tap a subject to protect it.") }
                return String(localized: "\(selection.pickedCount) of \(selection.groupCount) selected. Tap a subject to change it.")
            }
            return String(localized: "Auto protects the main subjects it finds.")
        }
    }

    static func notice(_ selection: SubjectSelection) -> String? {
        switch selection.notice {
        case .tooMuch?: return String(localized: "Too much of the photo is selected. Deselect a subject first.")
        case .tooLarge?: return String(localized: "This area is too large to be a subject.")
        case .nothingFound?: return String(localized: "No subject found there. Try another spot.")
        case nil:
            return selection.isSemiAuto && selection.showsOverlay && (selection.candidates?.merged ?? false)
                ? String(localized: "Many subjects were found. Nearby ones are grouped.") : nil
        }
    }

    /// Why Save waits, with the download's progress.
    static func modelWait(_ state: PreciseModelLoader.State) -> String {
        switch state {
        case .downloading(let fraction):
            return String(localized: "Labs subject emphasis needs a model that is still downloading (\(Int((fraction * 100).rounded()))%). Wait, or save this photo without subject emphasis.")
        case .failed:
            return String(localized: "The subject model couldn’t be downloaded. Check your connection, or save this photo without subject emphasis.")
        case .waitingForNetwork:
            return String(localized: "Connect to the internet to download the subject model, or save this photo without subject emphasis.")
        case .idle, .ready:
            return String(localized: "Getting the subject model ready…")
        }
    }

    /// What the line colours mean, while tier lines are on screen.
    static func legend(_ selection: SubjectSelection) -> String? {
        guard selection.isSemiAuto, selection.showsOverlay, selection.tiers != nil else { return nil }
        return String(localized: "Mint: subjects. Amber: the scene in front. Lavender: the scene further back. Tap any of them to turn it on or off.")
    }
}
