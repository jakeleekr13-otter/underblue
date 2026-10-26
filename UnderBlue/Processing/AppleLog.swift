import AVFoundation
import CoreImage
import CoreImage.CIFilterBuiltins
import simd

/// Apple Log and Apple Log 2 video. The white papers are in docs/Apple-log.
/// No Apple decoder removes the log curve. AVAssetReader, AVVideoComposition and VTPixelTransferSession
/// all pass the log signal through (measured 25 Oct 2026). Every frame path then hands Core Image the
/// signal tagged as sRGB. So decode() encodes the image back to sRGB to get the signal, and a Metal
/// kernel applies the curve.
enum AppleLog: Sendable, Equatable {
    case log, log2

    /// The value of the format description's log transfer function key. The CoreVideo names hold the same
    /// strings (CMFormatDescription.h) and exist from iOS 26; the CoreMedia name for Log 2 needs iOS 27.
    init?(identifier: String?) {
        if identifier == kCVImageBufferLogTransferFunction_AppleLog as String { self = .log }
        else if identifier == kCVImageBufferLogTransferFunction_AppleLog2 as String { self = .log2 }
        else { return nil }
    }

    init?(_ range: VideoMetadata.DynamicRange) {
        switch range {
        case .appleLog: self = .log
        case .appleLog2: self = .log2
        default: return nil
        }
    }

    /// The log format of the asset's first video track, or nil.
    static func of(_ asset: AVAsset) async throws -> AppleLog? {
        guard let track = try await asset.loadTracks(withMediaType: .video).first,
              let format = try await track.load(.formatDescriptions).first else { return nil }
        return AppleLog(identifier: CMFormatDescriptionGetExtension(format,
            extensionKey: kCMFormatDescriptionExtension_LogTransferFunction) as? String)
    }

    /// Scene light at the top code value: 1200% reflectance (white paper table).
    static let sceneHeadroom: Float = 12
    /// Core Image's headroom for an HLG frame (measured on hlg_10bit.mov). decode() rolls the highlights
    /// off to it. Light up to 1.0 stays as it is, so a log clip then goes on like an HLG clip.
    static let hlgHeadroom: Float = 4.926

    /// The white paper's decoding function. The kernel holds the same curve; tests compare the two.
    static func linear(_ p: Float) -> Float {
        let r0: Float = -0.05641088, rt: Float = 0.01, c: Float = 47.28711236
        let beta: Float = 0.00964052, gamma: Float = 0.08550479, delta: Float = 0.69336945
        let pt = c * (rt - r0) * (rt - r0)
        if p >= pt { return exp2((p - delta) / gamma) - beta }
        if p >= 0 { return (p / c).squareRoot() + r0 }
        return r0
    }

    /// Linear Rec.2020 from this format's linear RGB. Apple Log is already Rec.2020.
    /// Apple Log 2 uses Apple Wide Gamut (Apple Log 2 white paper, page 6). Both use D65 white.
    var toRec2020: simd_double3x3 {
        switch self {
        case .log: return matrix_identity_double3x3
        case .log2:
            return Self.rgbToXYZ(red: (0.708, 0.292), green: (0.170, 0.797), blue: (0.131, 0.046)).inverse
                * Self.rgbToXYZ(red: (0.725, 0.301), green: (0.221, 0.814), blue: (0.068, -0.076))
        }
    }

    /// The RGB to XYZ matrix of a set of primaries with D65 white.
    static func rgbToXYZ(red: (Double, Double), green: (Double, Double), blue: (Double, Double)) -> simd_double3x3 {
        func xyz(_ c: (Double, Double)) -> simd_double3 { simd_double3(c.0 / c.1, 1, (1 - c.0 - c.1) / c.1) }
        let primaries = simd_double3x3(columns: (xyz(red), xyz(green), xyz(blue)))
        let scale = primaries.inverse * xyz((0.3127, 0.3290))
        return primaries * simd_double3x3(diagonal: scale)
    }

    private static let kernel = MetalKernels.color("UnderBlueAppleLogDecode")
    private static let srgb = CGColorSpace(name: CGColorSpace.sRGB)!
    private static let linearRec2020 = CGColorSpace(name: CGColorSpace.extendedLinearITUR_2020)!

    /// The frame as light in the working space, with HLG's headroom. Without the kernel the frame
    /// stays as it came, flat and grey, because no other decoder exists.
    func decode(_ image: CIImage) -> CIImage {
        guard let kernel = Self.kernel else { return image }
        let signal = image.matchedFromWorkingSpace(to: Self.srgb) ?? image
        let rows = toRec2020.transpose
        let vector = { (row: simd_double3) in CIVector(x: row.x, y: row.y, z: row.z) }
        guard let light = kernel.apply(extent: signal.extent, arguments: [signal, vector(rows.columns.0),
                                                                          vector(rows.columns.1), vector(rows.columns.2)]),
              let working = light.matchedToWorkingSpace(from: Self.linearRec2020) else { return image }
        let tone = CIFilter.toneMapHeadroom()
        tone.inputImage = working.settingContentHeadroom(Self.sceneHeadroom)
        tone.sourceHeadroom = Self.sceneHeadroom
        tone.targetHeadroom = Self.hlgHeadroom
        return (tone.outputImage ?? working).settingContentHeadroom(Self.hlgHeadroom)
    }
}
