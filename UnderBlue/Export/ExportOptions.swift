import Foundation
import ImageIO
import UniformTypeIdentifiers

struct ExportOptions: Sendable {
    /// Quick is at most 720p and 30 fps, the fastest export (Jake, 10 Nov 2026). A smaller or slower source keeps its value.
    enum Resolution: String, CaseIterable, Identifiable, Sendable {
        case source = "Original resolution", hd = "1080p", quick = "Quick"
        var id: String { rawValue }
        var localizedName: String { String(localized: String.LocalizationValue(rawValue)) }
    }
    /// The video bitrate level. Size and frame rate stay the same. Standard is the bitrate before 10 Nov 2026.
    enum Quality: String, CaseIterable, Identifiable, Sendable {
        case high = "High", standard = "Standard", small = "Small"
        var id: String { rawValue }
        var localizedName: String { String(localized: String.LocalizationValue(rawValue)) }
        /// Applied to the Standard bitrate (Jake, 10 Nov 2026). The 100 Mbps cap stays.
        var bitrateFactor: Double {
            switch self {
            case .high: 1.5
            case .standard: 1
            case .small: 0.5
            }
        }
    }
    enum Range: String, CaseIterable, Identifiable, Sendable {
        case sdr = "SDR", hdr = "HDR"
        var id: String { rawValue }
    }
    /// Photo file type. Both save at quality 1. Below it, ImageIO wrote JPEG with half-resolution colour (4:2:0).
    /// HEIC also keeps 10 bits per channel, so smooth water gradients don't band.
    enum PhotoFormat: String, CaseIterable, Identifiable, Sendable {
        case jpeg, heic
        var id: String { rawValue }
        var name: String { rawValue.uppercased() }
        var fileExtension: String { self == .jpeg ? "jpg" : "heic" }
        var type: UTType { self == .jpeg ? .jpeg : .heic }
        /// HEIC needs an encoder on this device. JPEG is always there.
        static let available: [Self] = allCases.filter {
            $0 == .jpeg || (CGImageDestinationCopyTypeIdentifiers() as? [String] ?? []).contains(UTType.heic.identifier)
        }
    }
    /// A new resolution goes back to its own default quality.
    var resolution: Resolution = .source { didSet { if resolution != oldValue { chosenQuality = nil } } }
    var range: Range = .sdr
    /// The level the user picked for this resolution. Nil keeps the resolution's default.
    var chosenQuality: Quality?
    /// Quality depends on the resolution (Jake, 10 Nov 2026): each starts at its own default (Original High,
    /// 1080p Standard, Quick Small), and Pro can change it on all three. Free stays Standard (`allows`).
    var quality: Quality {
        get { chosenQuality ?? Self.defaultQuality(for: resolution) }
        set { chosenQuality = newValue }
    }
    static func defaultQuality(for resolution: Resolution) -> Quality {
        switch resolution {
        case .source: .high
        case .hd: .standard
        case .quick: .small
        }
    }
    var photoFormat: PhotoFormat = .jpeg
    var durationLimit: Double?
    /// Free exports carry the UnderBlue mark (Watermark). Pro exports never do.
    var watermark = false
    /// The resolution, range and quality from before the free limits. Only `applyTrial` sets it.
    var beforeTrial: (resolution: Resolution, range: Range, chosenQuality: Quality?)? = nil
    /// The one place that sets the free-trial limits. Free: 1080p SDR at Standard quality, the first
    /// `TrialPolicy.videoSeconds`, the mark. Pro: no time limit and no mark. The choices from before the free limits
    /// come back, so a purchase in the same editor gets the full choice (flow review 6.6, Jake 4 Nov 2026).
    mutating func applyTrial(_ free: Bool) {
        if free {
            // Keep the first values only. The export applies the limits again to its copy of the options.
            if beforeTrial == nil { beforeTrial = (resolution, range, chosenQuality) }
            resolution = .hd; range = .sdr; chosenQuality = nil; durationLimit = TrialPolicy.videoSeconds; watermark = true
        } else {
            if let beforeTrial {
                // The resolution first: setting it clears the chosen quality.
                resolution = beforeTrial.resolution; range = beforeTrial.range; chosenQuality = beforeTrial.chosenQuality
                self.beforeTrial = nil
            }
            durationLimit = nil; watermark = false
        }
    }
    /// Video output never exceeds 4K (3840 × 2160, either orientation). An 8K source exports at 4K.
    /// 8K peaked at 5.2 GB on a Mac even with the memory limit set, and the default build did not finish 60
    /// frames in 86 minutes. An iPhone 17 has about 3 GB free for the app (22 Oct 2026, docs/PerformanceMeasurement.md).
    static let maximumLongSide: CGFloat = 3840
    static let maximumShortSide: CGFloat = 2160
    /// A source clearly beyond 4K. DCI 4K (4096 wide) is not counted: it is only scaled to fit.
    static func exceedsSupportedSize(_ source: CGSize) -> Bool {
        max(source.width, source.height) > 4096
    }
    /// 4K is the best output the app makes: the original size of a 4K source, or an 8K source brought down to 4K.
    static func isBest(_ source: CGSize) -> Bool {
        max(ExportOptions().size(for: source).width, ExportOptions().size(for: source).height) >= maximumLongSide - 2
    }
    /// Free video exports are 1080p at Standard quality only (Jake, 10 Nov 2026). The picker and the estimate use this.
    static func allows(_ resolution: Resolution, pro: Bool) -> Bool { pro || resolution == .hd }
    static func allows(_ quality: Quality, pro: Bool) -> Bool { pro || quality == .standard }
    /// Quick keeps at most this many frames per second.
    static let quickFrameRate: Float = 30
    func size(for source: CGSize) -> CGSize {
        let longSide = max(source.width, source.height), shortSide = min(source.width, source.height)
        let choiceScale: CGFloat = switch resolution {
        case .source: 1
        case .hd: min(1, 1920 / longSide, 1080 / shortSide)
        case .quick: min(1, 1280 / longSide, 720 / shortSide)
        }
        let scale = min(choiceScale, Self.maximumLongSide / longSide, Self.maximumShortSide / shortSide)
        // Encoders require even dimensions. Never enlarge the source.
        return CGSize(width: max(2, floor(source.width * scale / 2) * 2), height: max(2, floor(source.height * scale / 2) * 2))
    }
    /// Every n-th source frame on average: 1 keeps them all. Quick keeps at most `quickFrameRate`. A 60 fps source keeps
    /// every 2nd frame, 120 fps every 4th, 50 fps every 2nd (25 fps). A source at 30 fps or less keeps every frame.
    func frameStep(sourceRate: Float) -> Int {
        guard resolution == .quick, sourceRate > Self.quickFrameRate + 0.5 else { return 1 }
        return Int((Double(sourceRate) / Double(Self.quickFrameRate) - 0.01).rounded(.up))
    }
    /// The frame rate of the output file.
    func outputFrameRate(sourceRate: Float) -> Float { sourceRate / Float(frameStep(sourceRate: sourceRate)) }
    func summary(for metadata: VideoMetadata) -> String {
        let size = size(for: metadata.displaySize)
        let dynamicRange = String(localized: String.LocalizationValue(range.rawValue))
        let step = frameStep(sourceRate: metadata.frameRate)
        let rate = step > 1 ? " · " + Self.frameRateText(outputFrameRate(sourceRate: metadata.frameRate)) : ""
        return "\(Int(size.width)) × \(Int(size.height))\(rate) · \(dynamicRange) · HEVC" + (range == .hdr ? " · 10-bit" : "")
    }
    /// "30 fps", "29.97 fps", "25 fps".
    static func frameRateText(_ rate: Float) -> String {
        let rounded = (Double(rate) * 100).rounded() / 100
        return (rounded == rounded.rounded() ? String(Int(rounded)) : String(format: "%.2f", rounded)) + " fps"
    }
}

/// Keeps source frames on a fixed time grid, so Quick drops frames by time, not by count. The export keeps variable
/// source timing, and a dropped source frame must not shift the later ones (roadmap 7.1 notes).
struct FrameRateLimiter {
    /// Seconds between kept frames. 0 keeps every frame.
    let interval: Double
    private var next: Double?

    init(sourceRate: Float, step: Int) {
        interval = step > 1 && sourceRate > 0 ? Double(step) / Double(sourceRate) : 0
    }

    mutating func keeps(_ time: Double) -> Bool {
        guard interval > 0 else { return true }
        // A quarter interval of slack absorbs timing jitter in the source.
        if let next, time < next - interval / 4 { return false }
        let slot = next ?? time
        // Stay on the grid, unless the source skipped ahead by more than half an interval.
        next = time - slot > interval / 2 ? time + interval : slot + interval
        return true
    }
}
/// The photo format last chosen in the editor or the batch screen. Both use it.
struct PhotoFormatStore {
    static let key = "photoFormat.v1"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    /// JPEG when nothing is saved, the value is unknown, or this device can't write the saved format.
    func load() -> ExportOptions.PhotoFormat {
        guard let raw = defaults.string(forKey: Self.key), let format = ExportOptions.PhotoFormat(rawValue: raw),
              ExportOptions.PhotoFormat.available.contains(format) else { return .jpeg }
        return format
    }

    func save(_ format: ExportOptions.PhotoFormat) { defaults.set(format.rawValue, forKey: Self.key) }
}
struct StorageCheck {
    static func require(bytes: Int64) throws {
        let values = try TemporaryFiles.directory.deletingLastPathComponent().resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        if let available = values.volumeAvailableCapacityForImportantUsage, available < bytes + 100_000_000 { throw UnderBlueError.storage }
    }
}
