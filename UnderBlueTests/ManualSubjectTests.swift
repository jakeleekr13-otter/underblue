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
