import CoreImage
import Darwin
import ImageIO
import Vision
import XCTest
@testable import UnderBlue

/// R8 of docs/ManualSubject.md: the time and peak memory of one press on the device. It reads the
/// photos in Documents/press-in (copy them there with `devicectl device copy to`) and is skipped without them.
final class PressProbeTests: XCTestCase {
    /// Press points by file name, top left 0-1. The second list is the included points of a fix-up press.
    private let presses: [String: [(String, CGPoint, [CGPoint])]] = [
        "IMG_20230118_093746_0014.JPEG": [("face", CGPoint(x: 0.483, y: 0.682), []), ("hand", CGPoint(x: 0.644, y: 0.761), [])],
        "DSC03545.JPG": [("leftDiver", CGPoint(x: 0.567, y: 0.333), []),
                         ("bothDivers", CGPoint(x: 0.567, y: 0.333), [CGPoint(x: 0.708, y: 0.300)])],
    ]

    private static func footprint() -> UInt64 { FootprintSampler.footprint() }

    /// Runs `body` while a thread samples the footprint every 2 ms. Returns the time and the peak over the start.
    private func measure(_ body: () async -> SubjectMask?) async -> (ms: Double, peakMB: Double, mask: SubjectMask?) {
        let sampler = FootprintSampler()
        sampler.begin()
        let t = Date()
        let mask = await body()
        let ms = Date().timeIntervalSince(t) * 1000
        return (ms, sampler.end(), mask)
    }

    /// The preview render behind the subject strength slider: no lift, picks without the lift (strength 0),
    /// and picks with the lift. Three rounds each, in this order.
    func testPreviewTimeWithSubjectStrength() async throws {
        guard #available(iOS 27.0, macOS 27.0, *) else { throw XCTSkip("needs iOS 27") }
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let input = documents.appendingPathComponent("press-in")
        try XCTSkipUnless(FileManager.default.fileExists(atPath: input.path), "no press-in folder")
        let usable = await SubjectMask.preciseModelUsable()
        try XCTSkipUnless(usable, "model not ready")
        for (name, list) in presses.sorted(by: { $0.key < $1.key }) {
            let url = input.appendingPathComponent(name)
            guard FileManager.default.fileExists(atPath: url.path), let first = list.first else { continue }
            let processor = PhotoProcessor()
            var settings = FilterSettings()
            settings.analysis = try await processor.analyze(url)
            let mask = try await processor.pressMask(url, at: first.1)
            let choices: [(String, SubjectChoice)] = [("off", .off), ("picked 0%", .picked(mask, strength: 0)),
                                                      ("picked 100%", .picked(mask)), ("picked 120%", .picked(mask, strength: 1.2))]
            for (label, choice) in choices {
                for round in 1...3 {
                    let t = Date()
                    _ = try await processor.preview(url, settings: settings, original: false, maxPixel: 1600, subjects: choice)
                    print(String(format: "PREVIEW %@ %@ round %d: %.0f ms", name, label, round, Date().timeIntervalSince(t) * 1000))
                }
            }
        }
    }

    /// Renders one photo through the app's preview path with several subject choices, as PNGs, to see what a
    /// choice changes around the subject. Set TEST_RUNNER_UB_PRESS_FILE, TEST_RUNNER_UB_PRESS_POINT
    /// ("x,y", top left 0-1), TEST_RUNNER_UB_PRESS_OUT, and optionally TEST_RUNNER_UB_PRESS_INTENSITY and _STRENGTHS.
    func testRenderSubjectChoicesForComparison() async throws {
        guard #available(iOS 27.0, macOS 27.0, *) else { throw XCTSkip("needs iOS 27") }
        let env = ProcessInfo.processInfo.environment
        guard let file = env["UB_PRESS_FILE"], let out = env["UB_PRESS_OUT"],
              let xy = env["UB_PRESS_POINT"]?.split(separator: ",").compactMap({ Double($0) }), xy.count == 2 else {
            throw XCTSkip("UB_PRESS_FILE, UB_PRESS_POINT or UB_PRESS_OUT is not set")
        }
        // A fresh simulator has no model yet: download it once, as PreciseModelLoader does.
        if !(await SubjectMask.preciseModelUsable()) {
            try await SubjectMask.downloadPreciseModel(progress: ProgressManager(totalCount: 1).subprogress(assigningCount: 1))
        }
        let usable = await SubjectMask.preciseModelUsable()
        try XCTSkipUnless(usable, "model not ready")
        // On a device the paths are inside the app's Documents (copy the photo there with `devicectl device copy to`).
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let url = file.hasPrefix("/") ? URL(fileURLWithPath: file) : documents.appendingPathComponent(file)
        let folder = out.hasPrefix("/") ? URL(fileURLWithPath: out, isDirectory: true) : documents.appendingPathComponent(out, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let processor = PhotoProcessor()
        var settings = FilterSettings()
        settings.analysis = try await processor.analyze(url)
        if let i = env["UB_PRESS_INTENSITY"].flatMap(Float.init) { settings.intensity = i }
        let mask = try await processor.pressMask(url, at: CGPoint(x: xy[0], y: xy[1]))
        if let mask {
            let data = mask.values.withUnsafeBytes { Data($0) }
            try data.write(to: folder.appendingPathComponent("mask_\(mask.width)x\(mask.height).raw"))
        }
        // TEST_RUNNER_UB_PRESS_STRENGTHS="1.35,1.4" renders 100 % and these strengths instead of the default set.
        let strengths = env["UB_PRESS_STRENGTHS"]?.split(separator: ",").compactMap { Float($0) } ?? []
        let choices: [(String, SubjectChoice)] = strengths.isEmpty
            ? [("off", .off), ("auto", .auto), ("picked000", .picked(mask, strength: 0)),
               ("picked100", .picked(mask)), ("picked130", .picked(mask, strength: 1.3))]
            : [("picked100", .picked(mask))] + strengths.map { (String(format: "picked%03d", Int(($0 * 100).rounded())), .picked(mask, strength: $0)) }
        for (label, choice) in choices {
            let image = try await processor.preview(url, settings: settings, original: false, maxPixel: 1600, subjects: choice)
            let target = folder.appendingPathComponent("\(label).png")
            guard let destination = CGImageDestinationCreateWithURL(target as CFURL, "public.png" as CFString, 1, nil) else { continue }
            CGImageDestinationAddImage(destination, image, nil)
            XCTAssertTrue(CGImageDestinationFinalize(destination))
            print("PRESSRENDER \(label) -> \(target.path)")
        }
    }

    func testPressTimeAndMemory() async throws {
        guard #available(iOS 27.0, macOS 27.0, *) else { throw XCTSkip("needs iOS 27") }
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let input = documents.appendingPathComponent("press-in")
        try XCTSkipUnless(FileManager.default.fileExists(atPath: input.path), "no press-in folder")
        let usable = await SubjectMask.preciseModelUsable()
        print("PRESS model usable: \(usable)")
        try XCTSkipUnless(usable, "model not ready")
        let context = FilterEngine().context
        for (name, list) in presses.sorted(by: { $0.key < $1.key }) {
            let url = input.appendingPathComponent(name)
            guard let image = CIImage(contentsOf: url, options: [.applyOrientationProperty: true]) else { print("PRESS \(name): missing"); continue }
            for (label, p, extra) in list {
                let seed = NormalizedPoint(x: p.x, y: 1 - p.y)
                let included = extra.map { NormalizedPoint(x: $0.x, y: 1 - $0.y) }
                for round in 1...3 {
                    let r = await measure { await SubjectMask.precise(image, point: seed, included: included, context: context) }
                    let share = r.mask.map { $0.values.reduce(0, +) / Float($0.values.count) } ?? -1
                    print(String(format: "PRESS %@ %@ round %d: %.0f ms, peak +%.0f MB, share %.4f, footprint %.0f MB",
                                 name, label, round, r.ms, r.peakMB, share, Double(Self.footprint()) / 1_048_576))
                }
            }
        }
    }
}
