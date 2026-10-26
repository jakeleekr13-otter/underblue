import CoreImage
import SwiftUI
import XCTest
@testable import UnderBlue

/// Manual mode and the subject strength (docs/ManualSubject.md).
final class ManualSubjectTests: XCTestCase {
    /// A 4 x 4 mask with 1 on the given cells, row 0 on top.
    private func mask(_ cells: [Int]) -> SubjectMask {
        var values = [Float](repeating: 0, count: 16)
        for c in cells { values[c] = 1 }
        return SubjectMask(width: 4, height: 4, values: values)
    }

    func testStrengthScalesTheWholeRecipe() throws {
        let lift = SubjectLift(mask: mask([0]))
        XCTAssertEqual(lift.scaled(1), lift, "100% is the lift Auto applies")
        XCTAssertNil(lift.scaled(0), "0% is no lift")
        let strong = try XCTUnwrap(lift.scaled(1.5))
        XCTAssertEqual(strong.strength, lift.strength * 1.5, accuracy: 1e-6)
        XCTAssertEqual(strong.contrast, lift.contrast * 1.5, accuracy: 1e-6)
        XCTAssertEqual(strong.detail, lift.detail * 1.5, accuracy: 1e-6)
        XCTAssertEqual(strong.clarity, lift.clarity * 1.5, accuracy: 1e-6)
        XCTAssertEqual(strong.chromaCap, lift.chromaCap, "limits do not scale")
        XCTAssertEqual(strong.highlights, lift.highlights)
        XCTAssertEqual(try XCTUnwrap(lift.scaled(10)).strength, 0.9, "the gamma stays below 1")
    }

    func testApplyingFollowsTheStrength() throws {
        let map = try NormalizedDepthMap(width: 4, height: 4, values: .init(repeating: 0.6, count: 16))
        let plan = RestorationPlan(depth: map, depthSource: .monocular,
            depthStatistics: .init(minimum: 0.6, maximum: 0.6, median: 0.6), backscatterInfinity: .init(0.043, 0.086, 0.121),
            betaDirect: .init(1.2, 0.6, 0.4), betaBackscatter: .init(1.2, 1.6, 1.6), confidence: 0.8, limits: .init(),
            transmissionFloorPixelPercentage: 0, maximumGainPixelPercentage: 0)
        let picked = mask([5])
        XCTAssertEqual(PhotoProcessor.applying(.picked(picked), to: plan)?.subjectLift, SubjectLift(mask: picked))
        let off = PhotoProcessor.applying(.picked(picked, strength: 0), to: plan)
        XCTAssertNil(off?.subjectLift, "0%: no lift")
        XCTAssertEqual(off?.subjectMask, picked, "0% still keeps the picks out of the local veil")
        XCTAssertEqual(PhotoProcessor.applying(.picked(picked, strength: 1.5), to: plan)?.subjectLift, SubjectLift(mask: picked).scaled(1.5))
    }

    func testSubjectLiftWorksAtIntensityZero() throws {
        let engine = FilterEngine(), restoration = RestorationEngine()
        let side = 64
        let map = try NormalizedDepthMap(width: 4, height: 4, values: .init(repeating: 0.6, count: 16))
        let plan = RestorationPlan(depth: map, depthSource: .monocular,
            depthStatistics: .init(minimum: 0.6, maximum: 0.6, median: 0.6), backscatterInfinity: .init(0.043, 0.086, 0.121),
            betaDirect: .init(1.2, 0.6, 0.4), betaBackscatter: .init(1.2, 1.6, 1.6), confidence: 0.8, limits: .init(),
            transmissionFloorPixelPercentage: 0, maximumGainPixelPercentage: 0)
        // A mid-grey diver on blue water, the whole frame picked.
        let image = CIImage(color: CIColor(red: 0.2, green: 0.25, blue: 0.3, colorSpace: FilterEngine.workingSpace)!)
            .cropped(to: CGRect(x: 0, y: 0, width: side, height: side))
        var lift = SubjectLift(mask: SubjectMask(width: 4, height: 4, values: .init(repeating: 1, count: 16)))
        lift.tier2 = 0; lift.tier3 = 0
        var settings = FilterSettings(); settings.intensity = 0
        func luma(_ output: CIImage) -> Float {
            var pixel = [Float](repeating: 0, count: 4)
            engine.context.render(output, toBitmap: &pixel, rowBytes: 16, bounds: CGRect(x: 32, y: 32, width: 1, height: 1),
                                  format: .RGBAf, colorSpace: FilterEngine.workingSpace)
            return (SIMD3(pixel[0], pixel[1], pixel[2]) * ColorCorrection.luma).sum()
        }
        let untouched = luma(image)
        XCTAssertEqual(luma(try restoration.combined(image, plan: plan, settings: settings, filter: engine)), untouched, accuracy: 1e-5,
                       "Intensity 0 with no lift: the photo as it is")
        let lifted = luma(try restoration.combined(image, plan: plan, settings: settings, filter: engine, subjectLift: lift))
        XCTAssertGreaterThan(abs(lifted - untouched), 1e-3, "Intensity 0 still applies the subject lift")
        let stronger = luma(try restoration.combined(image, plan: plan, settings: settings, filter: engine, subjectLift: lift.scaled(1.5)))
        XCTAssertNotEqual(stronger, lifted, accuracy: 1e-4, "the subject strength still moves it")
        settings.preset = .original
        XCTAssertEqual(luma(try restoration.combined(image, plan: plan, settings: settings, filter: engine, subjectLift: lift)), untouched,
                       accuracy: 1e-5, "Original stays untouched")
    }

    func testAHoldInTheFrameMapsToTheImageAtAnyZoom() {
        let content = CGSize(width: 100, height: 50), container = CGSize(width: 100, height: 100)
        func point(_ x: CGFloat, _ y: CGFloat, _ zoom: PreviewZoom) -> CGPoint? {
            ZoomablePreview<EmptyView>.imagePoint(CGPoint(x: x, y: y), zoom: zoom, content: content, container: container)
        }
        XCTAssertEqual(point(50, 50, PreviewZoom()), CGPoint(x: 0.5, y: 0.5))
        XCTAssertEqual(point(0, 25, PreviewZoom()), CGPoint(x: 0, y: 0), "the image starts 25 pt down in the frame")
        XCTAssertNil(point(50, 10, PreviewZoom()), "above the image")
        let zoomed = PreviewZoom(scale: 2, offset: CGSize(width: 10, height: 0))
        XCTAssertEqual(point(50, 50, zoomed), CGPoint(x: 0.45, y: 0.5), "panned right by 10 pt at 2x: the centre shows x 0.45")
    }

    /// A 20 x 20 frame in the working space, row 0 on top: `near` colour in the top half, `far` in the bottom half.
    private func scene(near: SIMD3<Float>, far: SIMD3<Float>) -> CIImage {
        var rgba = [Float]()
        for y in 0..<20 { for _ in 0..<20 { let c = y < 10 ? near : far; rgba += [c.x, c.y, c.z, 1] } }
        return CIImage(bitmapData: rgba.withUnsafeBytes { Data($0) }, bytesPerRow: 20 * 16, size: CGSize(width: 20, height: 20),
                       format: .RGBAf, colorSpace: FilterEngine.workingSpace)
    }

    private func pixels(_ image: CIImage, _ engine: FilterEngine) -> [Float] {
        var out = [Float](repeating: 0, count: 20 * 20 * 4)
        engine.context.render(image, toBitmap: &out, rowBytes: 20 * 16, bounds: CGRect(x: 0, y: 0, width: 20, height: 20),
                              format: .RGBAf, colorSpace: FilterEngine.workingSpace)
        return out
    }

    /// Near (depth 0.1) in the top half, far (0.95) in the bottom half, as `scene`.
    private func splitPlan() throws -> RestorationPlan {
        let values = (0..<400).map { $0 < 200 ? Float(0.1) : 0.95 }
        let map = try NormalizedDepthMap(width: 20, height: 20, values: values)
        return RestorationPlan(depth: map, depthSource: .monocular,
            depthStatistics: .init(minimum: 0.1, maximum: 0.95, median: 0.5), backscatterInfinity: .init(0.043, 0.086, 0.121),
            betaDirect: .init(1.2, 0.6, 0.4), betaBackscatter: .init(1.2, 1.6, 1.6), confidence: 0.8, limits: .init(),
            transmissionFloorPixelPercentage: 0, maximumGainPixelPercentage: 0)
    }

    /// The object colour step (A2) sets one gain for the whole photo from what it measures. It must measure the
    /// frame before the subject lift: at 140 % the lift switched it on, and the water turned warm (squid, 26 Oct 2026).
    func testObjectColourStepTakesItsValuesFromTheMeasuredFrame() throws {
        let engine = FilterEngine(), restoration = RestorationEngine()
        let water = SIMD3<Float>(0.05, 0.14, 0.13)
        let tinted = scene(near: SIMD3(0.20, 0.30, 0.28), far: water)   // objects lean to the water: the step is on
        let warm = scene(near: SIMD3(0.30, 0.22, 0.15), far: water)     // a warm reef: the step is off
        let plan = try splitPlan()
        let depth = CIImage(bitmapData: plan.depth.values.withUnsafeBytes { Data($0) }, bytesPerRow: 20 * 4,
                            size: CGSize(width: 20, height: 20), format: .Rf, colorSpace: nil)
        let own = restoration.objectColour(tinted, plan: plan, depth: depth, redLoss: 0, context: engine.context)
        XCTAssertNotEqual(pixels(own, engine), pixels(tinted, engine), "measured on itself, the tinted frame gets the step")
        let measuredWarm = restoration.objectColour(tinted, measuredOn: warm, plan: plan, depth: depth, redLoss: 0, context: engine.context)
        XCTAssertEqual(pixels(measuredWarm, engine), pixels(tinted, engine), "measured on a frame with no step, nothing changes")
    }

    /// The subject strength changes the subject only. At the slider's top, every pixel outside the mask matches the
    /// photo with no lift, through the whole photo path.
    func testFullSubjectStrengthLeavesEverythingOutsideTheMask() throws {
        let engine = FilterEngine(), restoration = RestorationEngine()
        // Blue water and a dark subject at Intensity 10 %, like the squid. Before the fix the lift moved the water here
        // by about 0.057 (found by a sweep of near and water colours, 26 Oct 2026).
        let image = scene(near: SIMD3(0.10, 0.10, 0.20), far: SIMD3(0.02, 0.08, 0.16))
        let plan = try splitPlan()
        // The subject is the whole near half, so the lift moves the near mean the step measures.
        var values = [Float](repeating: 0, count: 400)
        for y in 0..<10 { for x in 0..<20 { values[y * 20 + x] = 1 } }
        var lift = SubjectLift(mask: SubjectMask(width: 20, height: 20, values: values))
        lift.tier2 = 0; lift.tier3 = 0
        var settings = FilterSettings(); settings.intensity = 0.1
        let plain = pixels(try restoration.combined(image, plan: plan, settings: settings, filter: engine), engine)
        for k: Float in [1, SubjectSelection.maximumStrength] {
            let strong = try XCTUnwrap(lift.scaled(k))
            let out = pixels(try restoration.combined(image, plan: plan, settings: settings, filter: engine, subjectLift: strong), engine)
            var inside: Float = 0
            for i in 0..<400 {
                let d = (0..<3).map { abs(out[i * 4 + $0] - plain[i * 4 + $0]) }.max() ?? 0
                if values[i] > 0 { inside = max(inside, d); continue }
                // The far half, clear of the mask's 1-cell ramp.
                let x = i % 20, y = i / 20
                guard y > 10 else { continue }
                // 1e-3: two render graphs round differently in half floats (about 2e-4 seen). The bug moved the water by 0.03 and more.
                XCTAssertEqual(d, 0, accuracy: 1e-3, "strength \(k): pixel \(x),\(y) outside the subject changed")
            }
            XCTAssertGreaterThan(inside, 1e-3, "strength \(k) changes the subject")
        }
    }

    func testPressedMasksBecomeGroupsInPressOrder() throws {
        let pressed = try XCTUnwrap(SubjectCandidates.pressed([mask([0, 1]), mask([15])]))
        XCTAssertEqual(pressed.groups.map(\.id), [0, 1])
        XCTAssertEqual(pressed.groupMask(at: CGPoint(x: 0.3, y: 0.1)), 0)
        XCTAssertEqual(pressed.groupMask(at: CGPoint(x: 0.9, y: 0.9)), 1)
        XCTAssertNil(pressed.groupMask(at: CGPoint(x: 0.6, y: 0.4)))
        XCTAssertNil(SubjectCandidates.pressed([]))
    }

    func testManualPressesAddRemoveAndReset() throws {
        var selection = SubjectSelection()
        selection.useManual()
        XCTAssertTrue(selection.isManual)
        XCTAssertTrue(selection.showsOverlay, "Manual needs no detection")
        XCTAssertEqual(selection.choice, .picked(nil), "no press yet: no subject")
        XCTAssertFalse(selection.showsStrength)

        let start = selection.key
        selection.startPress(at: CGPoint(x: 0.1, y: 0.1))
        XCTAssertEqual(selection.pressing, CGPoint(x: 0.1, y: 0.1))
        selection.finishPress(mask([0]))
        XCTAssertNil(selection.pressing)
        selection.finishPress(mask([15]))
        XCTAssertEqual(selection.presses.count, 2)
        XCTAssertNotEqual(selection.key, start)
        XCTAssertEqual(selection.choice, .picked(mask([0, 15])), "the presses as one mask")
        XCTAssertTrue(selection.showsStrength)

        XCTAssertEqual(selection.press(at: CGPoint(x: 0.9, y: 0.9)), 1, "a press on a picked subject finds it")
        XCTAssertNil(selection.press(at: CGPoint(x: 0.5, y: 0.5)))
        selection.removePress(1)
        XCTAssertEqual(selection.choice, .picked(mask([0])))

        selection.finishPress(nil)
        XCTAssertEqual(selection.notice, .nothingFound)
        XCTAssertEqual(selection.presses.count, 1)

        selection.setStrength(1.2)
        XCTAssertEqual(selection.choice, .picked(mask([0]), strength: 1.2))
        selection.setStrength(9)
        XCTAssertEqual(selection.strength, SubjectSelection.maximumStrength)

        selection.reset()
        XCTAssertTrue(selection.presses.isEmpty)
        XCTAssertEqual(selection.strength, 1, "reset returns the strength to 100%")
        XCTAssertTrue(selection.isManual, "reset keeps Manual")
    }

    func testManualRefusesPicksOverHalfTheFrame() {
        var selection = SubjectSelection()
        selection.useManual()
        selection.finishPress(mask(Array(0..<6)))
        selection.finishPress(mask(Array(8..<11)))
        XCTAssertEqual(selection.notice, .tooMuch, "6 + 3 of 16 cells is over half")
        XCTAssertEqual(selection.presses.count, 1)
        selection.finishPress(mask(Array(0..<10)))
        XCTAssertEqual(selection.notice, .tooLarge, "one press over half the frame")
    }

    func testStrengthBelongsToSemiAutoAndManualNotAuto() {
        var selection = SubjectSelection()
        let fish = SubjectGroup(id: 0, instances: [0], share: 0.0625, bounds: CGRect(x: 0, y: 0, width: 0.25, height: 0.25),
                                mask: mask([0]).values, fill: nil)
        selection.finishDetecting(SubjectCandidates(width: 4, height: 4, groups: [fish], merged: false))
        XCTAssertTrue(selection.isSemiAuto)
        XCTAssertTrue(selection.showsStrength)
        selection.setStrength(0.5)
        XCTAssertEqual(selection.choice, .picked(mask([0]), strength: 0.5))
        selection.useAuto()
        XCTAssertEqual(selection.choice, .auto, "Auto keeps the fixed lift")
        XCTAssertFalse(selection.showsStrength)
        selection.useManual()
        XCTAssertEqual(selection.choice, .picked(nil, strength: 0.5), "one strength per photo, shared by the two modes")
    }
}
