import SwiftUI

/// Pinch-to-zoom state for a still preview. Pure, so the limits can be unit tested.
struct PreviewZoom: Equatable {
    static let maximum: CGFloat = 4
    static let doubleTapScale: CGFloat = 2.5
    var scale: CGFloat = 1
    var offset: CGSize = .zero
    var isZoomed: Bool { scale > 1.01 }

    /// Keeps the scale in 1...maximum and the image edges outside the frame, so no gap opens.
    func clamped(content: CGSize, container: CGSize) -> PreviewZoom {
        let s = min(Self.maximum, max(1, scale.isFinite ? scale : 1))
        let limitX = max(0, (content.width * s - container.width) / 2)
        let limitY = max(0, (content.height * s - container.height) / 2)
        func clamp(_ value: CGFloat, _ limit: CGFloat) -> CGFloat { value.isFinite ? min(limit, max(-limit, value)) : 0 }
        return PreviewZoom(scale: s, offset: CGSize(width: clamp(offset.width, limitX), height: clamp(offset.height, limitY)))
    }

    /// Keeps the same image point at the centre when the frame changes size (rotation, fold, unfold).
    /// The scale stays; the offset follows the new fitted size and is clamped to the new frame.
    func resized(from old: CGSize, to new: CGSize, container: CGSize) -> PreviewZoom {
        let r = old.width > 0 && new.width > 0 ? new.width / old.width : 1
        return PreviewZoom(scale: scale, offset: CGSize(width: offset.width * r, height: offset.height * r))
            .clamped(content: new, container: container)
    }

    /// Size of an image with `pixels` fitted inside `container` (aspect fit).
    static func fitted(_ pixels: CGSize, in container: CGSize) -> CGSize {
        guard pixels.width > 0, pixels.height > 0, container.width > 0, container.height > 0 else { return .zero }
        let s = min(container.width / pixels.width, container.height / pixels.height)
        return CGSize(width: pixels.width * s, height: pixels.height * s)
    }
}

/// A photo preview that zooms with a pinch or a double tap and pans while zoomed.
/// The zoom state is owned by the caller, so swapping the image (Compare, a sharper render) keeps it.
///
/// `overlay` draws over the fitted image and zooms with it. It gets the fitted size. While `overlayActive`,
/// double tap zoom is off, so a quick second tap on a subject does not zoom. Pinch still zooms.
///
/// Pinch and pan are simultaneous gestures, so the overlay's own taps do not block them. A child view's
/// gesture takes a touch before the parent's `.gesture`, which stopped panning while the picker showed
/// (Jake, iPhone, 25 Oct 2026).
///
/// `onHold`: Manual subject picking (docs/ManualSubject.md). A finger kept still for `holdDuration` calls it with
/// the point, 0...1 from the image's top left. It is measured here, in the frame's space: in the overlay's space
/// the image moves with a pan, so a panning finger looked still and fired a pick.
struct ZoomablePreview<Overlay: View>: View {
    let image: CGImage
    @Binding var zoom: PreviewZoom
    var overlayActive = false
    var onZoomIn: () -> Void = {}
    var onHold: ((CGPoint) -> Void)? = nil
    let overlay: (CGSize) -> Overlay
    @State private var base = PreviewZoom()

    /// How long a press is held, and how far the finger may move on screen meanwhile.
    static var holdDuration: Duration { .milliseconds(500) }
    static var holdSlop: CGFloat { 10 }
    @State private var holdStart: CGPoint?
    @State private var holdDone = false
    @State private var holdTask: Task<Void, Never>?
    @State private var holds = 0

    init(image: CGImage, zoom: Binding<PreviewZoom>, overlayActive: Bool = false, onZoomIn: @escaping () -> Void = {},
         onHold: ((CGPoint) -> Void)? = nil, @ViewBuilder overlay: @escaping (CGSize) -> Overlay) {
        self.image = image; _zoom = zoom; self.overlayActive = overlayActive; self.onZoomIn = onZoomIn
        self.onHold = onHold; self.overlay = overlay
    }

    /// A point in the frame as a point on the image, 0...1 from its top left. Nil off the image.
    static func imagePoint(_ location: CGPoint, zoom: PreviewZoom, content: CGSize, container: CGSize) -> CGPoint? {
        guard content.width > 0, content.height > 0, zoom.scale > 0 else { return nil }
        let x = (location.x - container.width / 2 - zoom.offset.width) / zoom.scale + content.width / 2
        let y = (location.y - container.height / 2 - zoom.offset.height) / zoom.scale + content.height / 2
        let p = CGPoint(x: x / content.width, y: y / content.height)
        return (0...1).contains(p.x) && (0...1).contains(p.y) ? p : nil
    }

    private func holdGesture(content: CGSize, container: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { value in
                guard !holdDone, let onHold else { return }
                guard let start = holdStart else {
                    let start = value.startLocation
                    holdStart = start
                    let point = Self.imagePoint(start, zoom: zoom, content: content, container: container)
                    holdTask = Task { @MainActor in
                        try? await Task.sleep(for: Self.holdDuration)
                        guard !Task.isCancelled, holdStart == start, !holdDone else { return }
                        holdDone = true
                        if let point { holds += 1; onHold(point) }
                    }
                    return
                }
                let dx = value.location.x - start.x, dy = value.location.y - start.y
                if (dx * dx + dy * dy).squareRoot() > Self.holdSlop { holdTask?.cancel(); holdStart = nil; holdDone = true }
            }
            .onEnded { _ in holdTask?.cancel(); holdTask = nil; holdStart = nil; holdDone = false }
    }

    var body: some View {
        GeometryReader { geometry in
            let container = geometry.size
            let content = PreviewZoom.fitted(CGSize(width: image.width, height: image.height), in: container)
            Image(decorative: image, scale: 1).resizable()
                .frame(width: content.width, height: content.height)
                .overlay { overlay(content).frame(width: content.width, height: content.height) }
                .scaleEffect(zoom.scale)
                .offset(zoom.offset)
                .frame(width: container.width, height: container.height)
                .onChange(of: content) { old, new in
                    zoom = zoom.resized(from: old, to: new, container: container)
                    base = zoom
                }
                .contentShape(Rectangle())
                .simultaneousGesture(MagnifyGesture()
                    .onChanged { value in
                        zoom = PreviewZoom(scale: base.scale * value.magnification, offset: zoom.offset)
                            .clamped(content: content, container: container)
                    }
                    .onEnded { _ in finish() }
                    .simultaneously(with: DragGesture(minimumDistance: 1)
                        .onChanged { value in
                            // Panning only makes sense while zoomed; at 1x the image already fits.
                            guard zoom.isZoomed else { return }
                            let moved = CGSize(width: base.offset.width + value.translation.width,
                                               height: base.offset.height + value.translation.height)
                            zoom = PreviewZoom(scale: zoom.scale, offset: moved).clamped(content: content, container: container)
                        }
                        .onEnded { _ in finish() }))
                .gesture(TapGesture(count: 2).onEnded {
                    withAnimation(.snappy) {
                        zoom = zoom.isZoomed ? PreviewZoom()
                            : PreviewZoom(scale: PreviewZoom.doubleTapScale).clamped(content: content, container: container)
                    }
                    finish()
                }, isEnabled: !overlayActive)
                .simultaneousGesture(holdGesture(content: content, container: container), isEnabled: onHold != nil)
        }
        .sensoryFeedback(.impact(weight: .medium), trigger: holds)
        .accessibilityElement(children: overlayActive ? .contain : .ignore)
        .accessibilityLabel("Photo preview")
        .accessibilityValue(Text("\(Int((zoom.scale * 100).rounded()))%"))
        .accessibilityHint("Pinch or double-tap to zoom.")
        .accessibilityZoomAction { action in
            let step: CGFloat = action.direction == .zoomIn ? 1.5 : 1 / 1.5
            // Offset resets to the centre, which is always inside the limits.
            zoom = PreviewZoom(scale: zoom.scale * step).clamped(content: .zero, container: .zero)
            finish()
        }
    }

    private func finish() {
        base = zoom
        if zoom.isZoomed { onZoomIn() }
    }
}

/// A small spinner over the preview while a new render is on its way. It shows only after 0.3 s, so a quick
/// render does not flash it (Jake, 25 Oct 2026: the subject strength slider felt slow with no sign of work).
struct PreviewRenderingIndicator: View {
    let active: Bool
    @State private var shown = false

    var body: some View {
        Group {
            if shown {
                ProgressView().controlSize(.small).padding(8)
                    .background(.ultraThinMaterial, in: Circle())
                    .accessibilityLabel("Updating preview")
                    .transition(.opacity)
            }
        }
        .padding(10)
        .allowsHitTesting(false)
        .task(id: active) {
            guard active else { withAnimation { shown = false }; return }
            try? await Task.sleep(for: .milliseconds(300))
            if !Task.isCancelled { withAnimation { shown = true } }
        }
    }
}

extension ZoomablePreview where Overlay == EmptyView {
    init(image: CGImage, zoom: Binding<PreviewZoom>, onZoomIn: @escaping () -> Void = {}) {
        self.init(image: image, zoom: zoom, overlayActive: false, onZoomIn: onZoomIn) { _ in EmptyView() }
    }
}
