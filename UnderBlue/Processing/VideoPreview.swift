import AVFoundation
import CoreImage
import Synchronization

private final class VideoRestorationDiagnosticGate: Sendable {
    private let recordedRenderFallback = Mutex(false)

    func recordRenderFallback(using diagnostics: DiagnosticRecorder?) {
        let shouldRecord = recordedRenderFallback.withLock { recorded in
            defer { recorded = true }
            return !recorded
        }
        guard shouldRecord, let diagnostics else { return }
        Task {
            await diagnostics.record(.restorationFallback(.videoRender),
                                     operation: .videoRestoration)
        }
    }
}

final class PreviewSettings: Sendable {
    private let state = Mutex((settings: FilterSettings(), original: false))
    func update(_ settings: FilterSettings, comparing: Bool) {
        state.withLock { $0 = (settings, comparing) }
    }
    func snapshot() -> (FilterSettings, Bool) {
        state.withLock { ($0.settings, $0.original) }
    }
}

struct PreviewGeneration: Sendable, Equatable {
    private(set) var value: UInt64 = 0
    mutating func begin() -> UInt64 { value &+= 1; return value }
    func accepts(_ candidate: UInt64) -> Bool { candidate == value }
}

#if DEBUG
enum VideoDebugVariant: String, CaseIterable, Sendable {
    case original, current, restoration, combined, depth, confidence
}
#endif

struct VideoPreview {
    let engine = FilterEngine()
    let restorationEngine = RestorationEngine()
    let analyzer: VideoRestorationAnalyzer
    private let diagnostics: DiagnosticRecorder?
    private let diagnosticGate = VideoRestorationDiagnosticGate()
    /// Output pixels per second the preview may render. nil renders at full size.
    private let pixelRateBudget: Double?

    /// Measured on iPhone 17 (22 Oct 2026): about 31 million pixels per second plays smoothly.
    /// 1080p at 60 fps with 0.5 scale ran at 60 fps. 4K at 60 fps with 0.5 scale ran at 18 fps.
    static let phonePixelRateBudget = 30_000_000.0

    init(diagnostics: DiagnosticRecorder? = nil, pixelRateBudget: Double? = nil) {
        self.diagnostics = diagnostics
        self.pixelRateBudget = pixelRateBudget
        analyzer = VideoRestorationAnalyzer(diagnostics: diagnostics)
    }

    func analyze(_ url: URL, metadata: VideoMetadata) async throws -> VideoRestorationAnalysis {
        try await analyzer.analyze(url: url, metadata: metadata)
    }

    func item(_ url: URL, settings: PreviewSettings, analysis: VideoRestorationAnalysis? = nil) async throws -> AVPlayerItem {
        let asset = AVURLAsset(url: url)
        let item = AVPlayerItem(asset: asset)
        item.appliesPerFrameHDRDisplayMetadata = false
        item.videoComposition = try await composition(asset: asset, settings: settings, analysis: analysis)
        return item
    }

    /// Render scale that keeps the preview inside the pixel-rate budget. Export never uses it.
    static func renderScale(size: CGSize, frameDuration: CMTime, budget: Double?) -> Float {
        guard let budget, frameDuration.seconds > 0 else { return 1 }
        let pixelRate = Double(size.width * size.height) / frameDuration.seconds
        guard pixelRate > budget else { return 1 }
        return Float((budget / pixelRate).squareRoot())
    }

    /// A fresh composition is intentionally created for every preset revision.
    /// Reassigning a copied private CI composition does not reliably invalidate AVPlayer's rendered-frame cache.
    func composition(asset: AVAsset, settings: PreviewSettings,
                     analysis: VideoRestorationAnalysis? = nil) async throws -> AVVideoComposition {
        // An Apple Log frame reaches the filter as the log signal. It is decoded and tone mapped to SDR
        // the same way as in the export, for both the original and the corrected preview.
        let log = try await AppleLog.of(asset)
        // nonisolated(nonsending): the non-Sendable asset never leaves the caller's isolation.
        let filtered = try await AVVideoComposition(applyingFiltersTo: asset) { [engine, restorationEngine, diagnosticGate, diagnostics] request in
            let (current, original) = settings.snapshot()
            var source = log.map { engine.sdr($0.decode(request.sourceImage)) } ?? request.sourceImage
            guard !original else { return AVCIImageFilteringResult(resultImage: source, ciContext: engine.context) }
            // The Original preset shows the frame as it is, as its export does.
            if current.preset != .original, let analysis {
                source = analysis.stabilised(source, at: request.compositionTime.seconds)
            }
            let fallback = engine.apply(source, settings: current, edgeGuard: false, coresWater: false)
            guard let moment = analysis?.moment(at: request.compositionTime.seconds) else {
                return AVCIImageFilteringResult(resultImage: fallback, ciContext: engine.context)
            }
            let output: CIImage
            do {
                output = try restorationEngine.combined(source, moment: moment,
                                                         settings: current, filter: engine)
            } catch {
                diagnosticGate.recordRenderFallback(using: diagnostics)
                output = fallback
            }
            return AVCIImageFilteringResult(resultImage: output, ciContext: engine.context)
        }
        // The filtering initializer takes no color options, so tag SDR Rec. 709 output on a rebuilt
        // composition. Every other value, including the filter's compositor and instructions, is kept.
        let configuration = AVVideoComposition.Configuration(
            animationTool: filtered.animationTool,
            colorPrimaries: AVVideoColorPrimaries_ITU_R_709_2,
            colorTransferFunction: AVVideoTransferFunction_ITU_R_709_2,
            colorYCbCrMatrix: AVVideoYCbCrMatrix_ITU_R_709_2,
            customVideoCompositorClass: filtered.customVideoCompositorClass,
            frameDuration: filtered.frameDuration,
            instructions: filtered.instructions,
            outputBufferDescription: filtered.outputBufferDescription,
            perFrameHDRDisplayMetadataPolicy: filtered.perFrameHDRDisplayMetadataPolicy,
            renderScale: Self.renderScale(size: filtered.renderSize, frameDuration: filtered.frameDuration,
                                          budget: pixelRateBudget),
            renderSize: filtered.renderSize,
            sourceSampleDataTrackIDs: filtered.sourceSampleDataTrackIDs,
            sourceTrackIDForFrameTiming: filtered.sourceTrackIDForFrameTiming,
            spatialVideoConfigurations: filtered.spatialVideoConfigurations)
        return AVVideoComposition(configuration: configuration)
    }

    #if DEBUG
    func comparisonPreviews(analysis: VideoRestorationAnalysis, settings: FilterSettings) throws
        -> [VideoDebugVariant: CGImage] {
        let frame = CIImage(cgImage: analysis.representativeFrame)
        let source = AppleLog(analysis.sourceProfile.dynamicRange).map { engine.sdr($0.decode(frame)) } ?? frame
        let small = FilterEngine.downscaled(source, maxPixel: 1200)
        let current = engine.apply(small, settings: settings, edgeGuard: false, coresWater: false)
        var images: [VideoDebugVariant: CIImage] = [.original: small, .current: current]
        if let moment = analysis.moment(at: analysis.representativeTime), let plan = try? moment.plan(),
           let restored = try? restorationEngine.restore(small, plan: plan) {
            images[.restoration] = engine.blend(small, restored, amount: plan.confidence)
            images[.combined] = (try? restorationEngine.combined(small, moment: moment,
                                                                 settings: settings, filter: engine)) ?? current
            images[.depth] = depthVisualization(plan.depth, extent: small.extent)
            let weights = plan.effectiveChannelWeights
            images[.confidence] = CIImage(color: CIColor(red: CGFloat(weights.x), green: CGFloat(weights.y),
                                                         blue: CGFloat(weights.z), alpha: 1)).cropped(to: small.extent)
        } else {
            images[.restoration] = current; images[.combined] = current
        }
        var result: [VideoDebugVariant: CGImage] = [:]
        for (variant, image) in images {
            if let cg = engine.context.createCGImage(image, from: image.extent, format: .RGBA8,
                                                     colorSpace: FilterEngine.photoSpace) { result[variant] = cg }
        }
        return result
    }

    private func depthVisualization(_ map: NormalizedDepthMap, extent: CGRect) -> CIImage {
        var rgba = [Float](repeating: 0, count: map.values.count * 4)
        for index in map.values.indices {
            let value = map.values[index]
            rgba[index * 4] = value; rgba[index * 4 + 1] = value
            rgba[index * 4 + 2] = value; rgba[index * 4 + 3] = 1
        }
        let data = rgba.withUnsafeMutableBytes { Data($0) }
        let image = CIImage(bitmapData: data, bytesPerRow: map.width * 16,
                            size: CGSize(width: map.width, height: map.height), format: .RGBAf,
                            colorSpace: FilterEngine.workingSpace)
        return image.transformed(by: CGAffineTransform(scaleX: extent.width / CGFloat(map.width),
                                                        y: extent.height / CGFloat(map.height))).cropped(to: extent)
    }
    #endif
}
