import Foundation

/// The export time estimate with no probe (roadmap 7.4, Jake 9-10 Nov 2026): the output frame count times this
/// device's time per frame. The time per frame comes from the last probe or finished export, saved on the device.
/// The estimate is meant to be rough.
enum ExportSpeed {
    /// What one probe or export measured.
    struct Sample: Codable, Equatable, Sendable {
        /// Output pixels per frame.
        let pixels: Double
        let secondsPerFrame: Double
        /// Time outside the frame loop: setup, finishing and the output check.
        let setupSeconds: Double

        init(pixels: Double, secondsPerFrame: Double, setupSeconds: Double) {
            self.pixels = pixels
            self.secondsPerFrame = secondsPerFrame
            self.setupSeconds = setupSeconds
        }

        init?(_ result: VideoExportResult, outputSize: CGSize) {
            let pixels = Double(outputSize.width * outputSize.height)
            guard result.frames > 0, result.frameLoopSeconds > 0, pixels > 0 else { return nil }
            self.init(pixels: pixels, secondsPerFrame: result.frameLoopSeconds / Double(result.frames),
                      setupSeconds: max(0, result.elapsedSeconds - result.frameLoopSeconds))
        }

        /// Part of the cost per frame does not grow with the output size (decoding, encoder work).
        /// iPhone 17, 9 Nov 2026, estimates from 1 s probes of H.264 and HEVC clips at 60 and 120 fps: from 886 × 1920
        /// to 1182 × 2560 the pixels grew 1.78x and the time 1.39-1.55x. So 29-50% of the cost did not grow (mean 38%).
        static let fixedShare = 0.4

        /// Seconds per frame at another output size.
        func secondsPerFrame(atPixels target: Double) -> Double {
            secondsPerFrame * (Self.fixedShare + (1 - Self.fixedShare) * target / pixels)
        }
    }

    /// Which saved speed applies. The restoration and HDR change the cost per frame the most.
    struct Kind: Hashable, Sendable {
        let restoration: Bool
        let hdr: Bool
        var key: String { "\(restoration ? "restoration" : "original")-\(hdr ? "hdr" : "sdr")" }
    }

    /// The full export time in seconds for these options, or nil when it cannot be computed.
    /// Not modelled: Quick still decodes the frames it drops, so a Quick estimate from a 60 or 120 fps source is low.
    static func estimate(_ sample: Sample, options: ExportOptions, metadata: VideoMetadata) -> Double? {
        let size = options.size(for: metadata.displaySize)
        let length = min(metadata.duration, options.durationLimit ?? metadata.duration)
        let sourceRate = metadata.frameRate > 0 ? metadata.frameRate : 30
        let frames = Double(options.outputFrameRate(sourceRate: sourceRate)) * length
        let seconds = sample.setupSeconds + frames * sample.secondsPerFrame(atPixels: Double(size.width * size.height))
        return seconds.isFinite && seconds >= 0 ? seconds : nil
    }
}

/// One saved sample per kind on this device. A new iOS major version starts over, as the device profile does.
struct ExportSpeedStore {
    static let key = "exportSpeed.v1"
    private struct Entry: Codable {
        let systemMajorVersion: Int
        let sample: ExportSpeed.Sample
    }
    private let defaults: UserDefaults
    private let systemMajorVersion: Int

    init(defaults: UserDefaults = .standard,
         systemMajorVersion: Int = ProcessInfo.processInfo.operatingSystemVersion.majorVersion) {
        self.defaults = defaults
        self.systemMajorVersion = systemMajorVersion
    }

    func load(_ kind: ExportSpeed.Kind) -> ExportSpeed.Sample? {
        guard let data = defaults.data(forKey: Self.key),
              let entries = try? JSONDecoder().decode([String: Entry].self, from: data),
              let entry = entries[kind.key], entry.systemMajorVersion == systemMajorVersion else { return nil }
        return entry.sample
    }

    func save(_ sample: ExportSpeed.Sample, for kind: ExportSpeed.Kind) {
        var entries = defaults.data(forKey: Self.key).flatMap { try? JSONDecoder().decode([String: Entry].self, from: $0) } ?? [:]
        entries[kind.key] = Entry(systemMajorVersion: systemMajorVersion, sample: sample)
        if let data = try? JSONEncoder().encode(entries) { defaults.set(data, forKey: Self.key) }
    }
}
