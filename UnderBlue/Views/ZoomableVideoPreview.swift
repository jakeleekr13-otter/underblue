import AVKit
import SwiftUI

/// A video preview that zooms like the photo preview: pinch, double tap, and pan while zoomed (Roadmap 8.1).
///
/// The player view keeps its own controls. While zoomed, a second layer of the same player draws the zoomed
/// frame in the player's video overlay. That overlay sits above the video and below the controls.
/// So the video plays on while zoomed, and the controls stay usable.
///
/// `locked`: no zoom and no touches. Used while the scene is analysed (iPhone and Mac, Jake 11 Nov 2026).
struct ZoomableVideoPreview: View {
    let player: AVPlayer
    @Binding var zoom: PreviewZoom
    var locked = false
    @State private var base = PreviewZoom()
    /// The video's display size, after its rotation. Zero until loaded; no zoom until then.
    @State private var videoSize: CGSize = .zero

    var body: some View {
        GeometryReader { geometry in
            let container = geometry.size
            let content = PreviewZoom.fitted(videoSize, in: container)
            VideoPlayer(player: player) {
                if zoom.isZoomed { zoomedFrame(content: content, container: container) }
            }
            .disabled(locked).allowsHitTesting(!locked)
            .frame(width: container.width, height: container.height)
            .previewZoomGestures(zoom: $zoom, base: $base, content: content, container: container,
                                 enabled: !locked && content != .zero) { base = zoom }
            .onChange(of: content) { old, new in
                zoom = zoom.resized(from: old, to: new, container: container)
                base = zoom
            }
        }
        .task(id: ObjectIdentifier(player)) { videoSize = await Self.displaySize(player.currentItem?.asset) }
        .onChange(of: locked, initial: true) { _, locked in
            if locked { zoom = PreviewZoom(); base = zoom }
        }
        .accessibilityZoomAction { action in
            guard !locked, videoSize != .zero else { return }
            let step: CGFloat = action.direction == .zoomIn ? 1.5 : 1 / 1.5
            // Offset resets to the centre, which is always inside the limits.
            zoom = PreviewZoom(scale: zoom.scale * step).clamped(content: .zero, container: .zero)
            base = zoom
        }
    }

    /// The zoomed frame fills the player and covers the 1x video under it.
    /// The layer is sized up, not scaled, so it draws at the zoomed size.
    private func zoomedFrame(content: CGSize, container: CGSize) -> some View {
        ZStack {
            Color.black
            PlayerLayerView(player: player)
                .frame(width: content.width * zoom.scale, height: content.height * zoom.scale)
                .offset(zoom.offset)
        }
        .frame(width: container.width, height: container.height)
        .clipped()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// The size the video shows at: the track's natural size turned by its transform.
    static func displaySize(_ asset: AVAsset?) async -> CGSize {
        guard let asset, let track = try? await asset.loadTracks(withMediaType: .video).first,
              let (size, transform) = try? await track.load(.naturalSize, .preferredTransform) else { return .zero }
        return displaySize(natural: size, transform: transform)
    }

    nonisolated static func displaySize(natural: CGSize, transform: CGAffineTransform) -> CGSize {
        let rect = CGRect(origin: .zero, size: natural).applying(transform)
        return CGSize(width: abs(rect.width), height: abs(rect.height))
    }
}

/// A bare `AVPlayerLayer` for a player, with no controls and no touches.
#if os(iOS)
struct PlayerLayerView: UIViewRepresentable {
    let player: AVPlayer

    final class LayerView: UIView {
        override class var layerClass: AnyClass { AVPlayerLayer.self }
        var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
    }

    func makeUIView(context: Context) -> LayerView {
        let view = LayerView()
        view.isUserInteractionEnabled = false
        view.playerLayer.videoGravity = .resizeAspect
        view.playerLayer.player = player
        return view
    }

    func updateUIView(_ view: LayerView, context: Context) {
        if view.playerLayer.player !== player { view.playerLayer.player = player }
    }
}
#else
struct PlayerLayerView: NSViewRepresentable {
    let player: AVPlayer

    final class LayerView: NSView {
        let playerLayer = AVPlayerLayer()
        override init(frame: NSRect) {
            super.init(frame: frame)
            wantsLayer = true
            layer = playerLayer
        }
        required init?(coder: NSCoder) { nil }
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }

    func makeNSView(context: Context) -> LayerView {
        let view = LayerView()
        view.playerLayer.videoGravity = .resizeAspect
        view.playerLayer.player = player
        return view
    }

    func updateNSView(_ view: LayerView, context: Context) {
        if view.playerLayer.player !== player { view.playerLayer.player = player }
    }
}
#endif
