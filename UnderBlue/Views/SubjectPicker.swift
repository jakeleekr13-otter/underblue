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
}

/// Edge lines, fills and badges for the subject groups. Colour is not the only signal:
/// a selected group has a thick line, a check mark and a fill; a group that is not selected has
/// a thin line and an empty circle.
struct SubjectPicker: View {
    let candidates: SubjectCandidates
    let picks: Set<Int>
    /// Fitted size of the photo on screen, at zoom 1.
    let size: CGSize
    let zoom: CGFloat
    let onToggle: (Int) -> Void

    var body: some View {
        // Lines and badges keep their size on screen while the image zooms.
        let unit = 1 / max(1, zoom)
        ZStack(alignment: .topLeading) {
            Color.clear.contentShape(Rectangle())
                .onTapGesture(count: 1, coordinateSpace: .local) { location in
                    if let id = SubjectPickerGeometry.group(at: location, in: size, zoom: zoom, of: candidates) { onToggle(id) }
                }
            ForEach(candidates.groups) { group in
                groupView(group, selected: picks.contains(group.id), unit: unit)
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

    static func label(_ group: SubjectGroup, position: Int, selected: Bool) -> String {
        selected ? String(localized: "Subject group \(position), selected, \(group.instances.count) included")
            : String(localized: "Subject group \(position), not selected, \(group.instances.count) included")
    }
}

/// The text under the picker controls: what is selected, and why a tap did nothing.
enum SubjectPickerText {
    static func summary(_ selection: SubjectSelection) -> String {
        switch selection.status {
        case .detecting: return String(localized: "Looking for subjects…")
        case .none: return String(localized: "No subjects found. UnderBlue uses Auto.")
        case .idle: return String(localized: "Auto protects the main subjects it finds.")
        case .ready:
            if selection.isManual {
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
        case nil:
            return selection.showsOverlay && (selection.candidates?.merged ?? false)
                ? String(localized: "Many subjects were found. Nearby ones are grouped.") : nil
        }
    }
}
