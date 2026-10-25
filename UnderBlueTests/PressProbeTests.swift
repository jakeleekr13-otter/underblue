import CoreImage
import Darwin
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

    private static func footprint() -> UInt64 {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count) }
        }
        return result == KERN_SUCCESS ? info.phys_footprint : 0
    }

    /// Runs `body` while a thread samples the footprint every 2 ms. Returns the time and the peak over the start.
    private func measure(_ body: () async -> SubjectMask?) async -> (ms: Double, peakMB: Double, mask: SubjectMask?) {
        let start = Self.footprint()
        let peak = UnsafeMutablePointer<UInt64>.allocate(capacity: 1); peak.pointee = start
        let running = UnsafeMutablePointer<Bool>.allocate(capacity: 1); running.pointee = true
        defer { peak.deallocate(); running.deallocate() }
        let sampler = Thread { while running.pointee { peak.pointee = max(peak.pointee, Self.footprint()); usleep(2000) } }
        sampler.start()
        let t = Date()
        let mask = await body()
        let ms = Date().timeIntervalSince(t) * 1000
        running.pointee = false
        usleep(5000)
        return (ms, Double(Int64(peak.pointee) - Int64(start)) / 1_048_576, mask)
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
