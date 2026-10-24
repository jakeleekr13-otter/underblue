import XCTest
import CoreImage
@testable import UnderBlue

final class SubjectCandidatesTests: XCTestCase {
    private func instance(_ index: Int, _ x: CGFloat, _ y: CGFloat, _ w: CGFloat = 0.05, _ h: CGFloat = 0.05, share: Float = 0.01) -> SubjectInstance {
        SubjectInstance(index: index, bounds: CGRect(x: x, y: y, width: w, height: h), share: share)
    }

    /// A group with a square mask over `bounds`, on a 20 x 20 grid.
    private func group(_ id: Int, bounds: CGRect, share: Float, instances: [Int] = [1]) -> SubjectGroup {
        var mask = [Float](repeating: 0, count: 400)
        for y in 0..<20 { for x in 0..<20 {
            let px = (CGFloat(x) + 0.5) / 20, py = (CGFloat(y) + 0.5) / 20
            if bounds.contains(CGPoint(x: px, y: py)) { mask[y * 20 + x] = 1 }
        } }
        return SubjectGroup(id: id, instances: instances, share: share, bounds: bounds, mask: mask, fill: nil)
    }

    private func candidates(_ groups: [SubjectGroup]) -> SubjectCandidates {
        SubjectCandidates(width: 20, height: 20, groups: groups, merged: false)
    }

    // MARK: Grouping

    func testTwoCloseInstancesMakeOneGroupAndTwoFarOnesMakeTwo() {
        let close = SubjectCandidates.grouped([instance(1, 0.10, 0.10), instance(2, 0.17, 0.10)], aspect: 1)
        XCTAssertEqual(close.groups.count, 1)
        XCTAssertEqual(close.groups[0].map(\.index), [1, 2])
        let far = SubjectCandidates.grouped([instance(1, 0.05, 0.10), instance(2, 0.70, 0.10)], aspect: 1)
        XCTAssertEqual(far.groups.count, 2)
        XCTAssertFalse(far.merged)
    }

    func testAChainOfCloseInstancesIsOneGroup() {
        // A school: each fish is near the next one, the ends are far apart.
        let school = (0..<10).map { instance($0 + 1, 0.05 + CGFloat($0) * 0.085, 0.4, 0.05, 0.05, share: 0.002) }
        let result = SubjectCandidates.grouped(school, aspect: 1)
        XCTAssertEqual(result.groups.count, 1)
        XCTAssertEqual(result.groups[0].count, 10)
    }

    func testGapIsMeasuredInLongSidesOnATallPhoto() {
        // Two boxes with a horizontal gap of 0.06 of the width. On a square photo that is 0.06 long sides: two groups.
        let apart = [instance(1, 0.10, 0.4), instance(2, 0.21, 0.4)]
        XCTAssertEqual(SubjectCandidates.grouped(apart, aspect: 1).groups.count, 2)
        // On a photo half as wide as it is tall the same gap is 0.03 long sides: one group.
        XCTAssertEqual(SubjectCandidates.grouped(apart, aspect: 0.5).groups.count, 1)
        // A wide photo shrinks vertical gaps the same way.
        let stacked = [instance(1, 0.4, 0.10), instance(2, 0.4, 0.21)]
        XCTAssertEqual(SubjectCandidates.grouped(stacked, aspect: 1).groups.count, 2)
        XCTAssertEqual(SubjectCandidates.grouped(stacked, aspect: 2).groups.count, 1)
    }

    func testTooManyInstancesAreCappedAndSmallestMergeFirst() {
        // Ten far-apart instances. Shares 0.10 down to 0.01.
        let many = (0..<10).map { i in instance(i + 1, CGFloat(i % 5) * 0.2, CGFloat(i / 5) * 0.5, 0.04, 0.04, share: 0.10 - Float(i) * 0.01) }
        let result = SubjectCandidates.grouped(many, aspect: 1)
        XCTAssertEqual(result.groups.count, SubjectCandidates.maximumGroups)
        XCTAssertTrue(result.merged)
        // Every instance is still in some group, and the groups run from the largest share down.
        XCTAssertEqual(Set(result.groups.flatMap { $0.map(\.index) }), Set(1...10))
        let shares = result.groups.map { $0.reduce(0) { $0 + $1.share } }
        XCTAssertEqual(shares, shares.sorted(by: >))
    }

    func testNoInstancesGiveNoGroups() {
        let result = SubjectCandidates.grouped([], aspect: 1)
        XCTAssertTrue(result.groups.isEmpty)
        XCTAssertFalse(result.merged)
    }

    // MARK: Picking and the cap

    func testMaskOfNothingPickedIsNilAndTwoGroupsUnion() {
        let a = group(0, bounds: CGRect(x: 0.0, y: 0.0, width: 0.3, height: 0.3), share: 0.09)
        let b = group(1, bounds: CGRect(x: 0.6, y: 0.6, width: 0.3, height: 0.3), share: 0.09)
        let all = candidates([a, b])
        XCTAssertNil(all.mask(picking: []))
        let one = all.mask(picking: [0])!
        XCTAssertEqual(one.values.reduce(0, +), 36, "6 x 6 cells")
        let both = all.mask(picking: [0, 1])!
        XCTAssertEqual(both.values.reduce(0, +), 72)
    }

    func testAPickThatWouldCoverTooMuchIsRefusedButRemovingIsAllowed() {
        let a = group(0, bounds: CGRect(x: 0, y: 0, width: 0.5, height: 0.5), share: 0.30)
        let b = group(1, bounds: CGRect(x: 0.5, y: 0.5, width: 0.5, height: 0.5), share: 0.30)
        let all = candidates([a, b])
        XCTAssertTrue(all.accepts(0, adding: []))
        XCTAssertFalse(all.accepts(1, adding: [0]), "0.60 is over the 0.50 cap")
        XCTAssertTrue(all.accepts(0, adding: [0]), "a group already picked can always be toggled off")
    }

    func testAGroupAboveTheCapCannotBePickedAlone() {
        var selection = SubjectSelection()
        selection.finishDetecting(candidates([group(0, bounds: CGRect(x: 0, y: 0, width: 1, height: 0.8), share: 0.80)]))
        XCTAssertTrue(selection.picks.isEmpty, "Auto would drop a mask this large")
        selection.toggle(0)
        XCTAssertTrue(selection.picks.isEmpty)
        XCTAssertEqual(selection.notice, .tooLarge)
    }

    // MARK: Hit test and coordinates

    func testHitTestUsesTheMaskThenTheGrownBox() {
        let a = group(0, bounds: CGRect(x: 0.1, y: 0.1, width: 0.2, height: 0.2), share: 0.04)
        let all = candidates([a])
        XCTAssertEqual(all.group(at: CGPoint(x: 0.2, y: 0.2), tolerance: 0), 0)
        XCTAssertNil(all.group(at: CGPoint(x: 0.5, y: 0.5), tolerance: 0.05))
        XCTAssertEqual(all.group(at: CGPoint(x: 0.33, y: 0.2), tolerance: 0.05), 0, "just outside the box, inside the tolerance")
        XCTAssertNil(all.group(at: CGPoint(x: .nan, y: 0.2), tolerance: 0.05))
    }

    func testTapMapsToTheSamePhotoPointAtEveryZoomAndAspect() {
        let a = group(0, bounds: CGRect(x: 0.1, y: 0.1, width: 0.2, height: 0.2), share: 0.04)
        let all = candidates([a])
        // The overlay lives inside the zoomed image, so its own space is the fitted image at zoom 1.
        for size in [CGSize(width: 400, height: 300), CGSize(width: 300, height: 400), CGSize(width: 200, height: 200)] {
            let inside = CGPoint(x: size.width * 0.2, y: size.height * 0.2)
            XCTAssertEqual(SubjectPickerGeometry.group(at: inside, in: size, zoom: 1, of: all), 0)
            XCTAssertEqual(SubjectPickerGeometry.group(at: inside, in: size, zoom: 4, of: all), 0)
            let outside = CGPoint(x: size.width * 0.8, y: size.height * 0.8)
            XCTAssertNil(SubjectPickerGeometry.group(at: outside, in: size, zoom: 1, of: all))
        }
        XCTAssertNil(SubjectPickerGeometry.normalized(.zero, in: .zero))
        // Zoomed in, the same tap size on screen covers less of the photo.
        let size = CGSize(width: 400, height: 300)
        XCTAssertLessThan(SubjectPickerGeometry.tolerance(in: size, zoom: 4), SubjectPickerGeometry.tolerance(in: size, zoom: 1))
    }

    // MARK: State

    func testAutoPicksMatchTheAutoMaskLimits() {
        let small = candidates([group(0, bounds: CGRect(x: 0, y: 0, width: 0.2, height: 0.2), share: 0.04)])
        XCTAssertEqual(SubjectSelection.autoPicks(small), [0])
        let tiny = candidates([group(0, bounds: CGRect(x: 0, y: 0, width: 0.05, height: 0.05), share: 0.002)])
        XCTAssertEqual(SubjectSelection.autoPicks(tiny), [], "under the 0.005 floor Auto has no mask")
        let reef = candidates([group(0, bounds: CGRect(x: 0, y: 0, width: 0.6, height: 0.6), share: 0.31)])
        XCTAssertEqual(SubjectSelection.autoPicks(reef), [], "31% is a reef; Auto drops it")
    }

    func testNoSubjectFoundKeepsAutoAndSaysSo() {
        var selection = SubjectSelection()
        selection.startDetecting()
        selection.finishDetecting(nil)
        XCTAssertEqual(selection.status, .none)
        XCTAssertFalse(selection.isManual)
        XCTAssertEqual(selection.choice, .auto)
        XCTAssertFalse(selection.showsOverlay)
    }

    func testManualStartsAsAutoThenFollowsTapsAndResetRestoresAuto() {
        var selection = SubjectSelection()
        let a = group(0, bounds: CGRect(x: 0, y: 0, width: 0.3, height: 0.3), share: 0.09)
        let b = group(1, bounds: CGRect(x: 0.6, y: 0.6, width: 0.3, height: 0.3), share: 0.09)
        selection.finishDetecting(candidates([a, b]))
        XCTAssertEqual(selection.picks, [0, 1])
        XCTAssertTrue(selection.showsOverlay)
        selection.toggle(1)
        XCTAssertEqual(selection.picks, [0])
        guard case .picked(let one?) = selection.choice else { return XCTFail("expected a mask") }
        XCTAssertEqual(one.values.reduce(0, +), 36)
        selection.toggle(0)
        XCTAssertEqual(selection.choice, .picked(nil), "None selected: no subject")
        selection.done()
        XCTAssertFalse(selection.showsOverlay)
        XCTAssertTrue(selection.isManual, "Done keeps Manual")
        selection.useAuto()
        XCTAssertEqual(selection.choice, .auto)
        selection.resumeManual()
        XCTAssertTrue(selection.picks.isEmpty, "the picks stayed in memory")
        selection.reset()
        XCTAssertEqual(selection.picks, [0, 1])
    }

    func testPickerSwitchIsOffByDefaultAndSavedOnTheDevice() {
        let suite = "SubjectPickerStoreTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        XCTAssertFalse(SubjectPickerStore(defaults: defaults).load(), "off by default")
        SubjectPickerStore(defaults: defaults).save(true)
        XCTAssertTrue(SubjectPickerStore(defaults: defaults).load(), "a new store reads the saved value")
        SubjectPickerStore(defaults: defaults).save(false)
        XCTAssertFalse(SubjectPickerStore(defaults: defaults).load())
    }

    // MARK: Tiers two and three

    func testTiersSplitNotWaterByTransmissionAndLeaveSubjectsAndWaterOut() throws {
        // 20 x 20. Left half water (share 1). Right half not water: top rows near (t 0.9), bottom rows far (t 0.2).
        // A Vision subject covers x 15...19, y 0...4.
        let w = 20, h = 20
        var share = [Float](repeating: 1, count: w * h), t = [Float](repeating: 0.9, count: w * h), subject = [Float](repeating: 0, count: w * h)
        for y in 0..<h { for x in 10..<w { share[y * w + x] = 0.1 } }
        for y in 10..<h { for x in 0..<w { t[y * w + x] = 0.2 } }
        for y in 0..<5 { for x in 15..<w { subject[y * w + x] = 1 } }
        let tiers = try XCTUnwrap(SubjectTiers.make(waterShare: share, transmission: t, subject: subject, width: w, height: h))
        XCTAssertEqual(tiers.tier2[2 * w + 12], 1, "near, not water")
        XCTAssertEqual(tiers.tier3[15 * w + 12], 1, "far, not water")
        XCTAssertEqual(tiers.tier2[2 * w + 17], 0, "a Vision subject is tier one")
        XCTAssertEqual(tiers.tier2[2 * w + 3] + tiers.tier3[15 * w + 3], 0, "open water is in no tier")
        XCTAssertNotNil(tiers.tier2Outline)
        XCTAssertNotNil(tiers.tier3Outline)
        XCTAssertFalse(tiers.isEmpty)
        XCTAssertNil(SubjectTiers.make(waterShare: share, transmission: [0.5], subject: nil, width: w, height: h), "sizes must match")
    }

    func testLightAtTheWatersDepthIsNoTier() throws {
        // 20 x 20, all at t 0.9. Open water (share 1, depth 0.95) fills rows 0...9.
        // Rows 10...14: bright light that fails the water test but sits at depth 0.9 (surface glow, bubbles).
        // Rows 15...19: an object in front, depth 0.4.
        let w = 20, h = 20
        var share = [Float](repeating: 1, count: w * h), depth = [Float](repeating: 0.95, count: w * h)
        let t = [Float](repeating: 0.9, count: w * h)
        for y in 10..<h { for x in 0..<w { share[y * w + x] = 0.1; depth[y * w + x] = y < 15 ? 0.9 : 0.4 } }
        XCTAssertEqual(SubjectTiers.waterDepth(waterShare: share, depth: depth), 0.95)
        let tiers = try XCTUnwrap(SubjectTiers.make(waterShare: share, transmission: t, subject: nil, depth: depth, width: w, height: h))
        XCTAssertEqual(tiers.tier2[12 * w + 5], 0, "light at the water's depth is not an object")
        XCTAssertEqual(tiers.tier2[17 * w + 5], 1, "the object in front stays")
        // No open water in the frame: the depth test is off, and the light counts.
        let noWater = [Float](repeating: 0.1, count: w * h)
        let without = try XCTUnwrap(SubjectTiers.make(waterShare: noWater, transmission: t, subject: nil, depth: depth, width: w, height: h))
        XCTAssertNil(SubjectTiers.waterDepth(waterShare: noWater, depth: depth))
        XCTAssertEqual(without.tier2[12 * w + 5], 1)
    }

    func testFlatSurfaceIsNoTierButATexturedOneIs() throws {
        // 40 x 40, nothing is water. Left half flat (sand), right half 2 px stripes (reef).
        // A 1 px checker would read 0: the central difference compares pixels of the same colour.
        let w = 40, h = 40
        var luma = [Float](repeating: 0.6, count: w * h)
        for y in 0..<h { for x in 20..<w { luma[y * w + x] = x % 4 < 2 ? 0.4 : 0.6 } }
        let texture = SubjectTiers.texture(luma: luma, width: w, height: h)
        XCTAssertEqual(texture[20 * w + 5], 0, accuracy: 0.0001, "flat")
        XCTAssertGreaterThan(texture[20 * w + 35], SubjectTiers.minimumTexture)
        let share = [Float](repeating: 0, count: w * h), t = [Float](repeating: 0.9, count: w * h)
        let tiers = try XCTUnwrap(SubjectTiers.make(waterShare: share, transmission: t, subject: nil, texture: texture, width: w, height: h))
        XCTAssertEqual(tiers.tier2[20 * w + 5], 0, "sand is no tier")
        XCTAssertEqual(tiers.tier2[20 * w + 35], 1, "a reef is")
    }

    func testTierCleanUpDropsSmallPiecesAndFillsSmallHoles() {
        let w = 10, h = 10
        var region = [Bool](repeating: false, count: w * h)
        for y in 0..<6 { for x in 0..<6 { region[y * w + x] = true } }
        region[2 * w + 2] = false          // a one-pixel hole
        region[9 * w + 9] = true           // a one-pixel speck
        let clean = SubjectTiers.cleaned(region, width: w, height: h, minimum: 3)
        XCTAssertTrue(clean[2 * w + 2], "the hole is filled")
        XCTAssertFalse(clean[9 * w + 9], "the speck is removed")
        XCTAssertTrue(clean[0], "the large piece stays")
    }

    func testChannelReadPutsTheTopRowFirst() {
        // Core Image's origin is at the bottom. A white band at the top of the extent must land in row 0.
        let context = CIContext(options: [.workingColorSpace: NSNull()])
        let black = CIImage(color: CIColor(red: 0, green: 0, blue: 0)).cropped(to: CGRect(x: 0, y: 0, width: 8, height: 8))
        let band = CIImage(color: CIColor(red: 1, green: 1, blue: 1)).cropped(to: CGRect(x: 0, y: 6, width: 8, height: 2))
        let values = SubjectTiers.channel(band.composited(over: black), 0, width: 8, height: 8, context: context)
        XCTAssertEqual(values[0], 1, accuracy: 0.01)
        XCTAssertEqual(values[7 * 8], 0, accuracy: 0.01)
    }

    // MARK: One place for the choice

    func testApplyingAChoiceChangesOnlyTheSubjectMask() throws {
        let map = try NormalizedDepthMap(width: 4, height: 4, values: .init(repeating: 0.6, count: 16))
        var plan = RestorationPlan(depth: map, depthSource: .monocular,
            depthStatistics: .init(minimum: 0.6, maximum: 0.6, median: 0.6), backscatterInfinity: .init(0.043, 0.086, 0.121),
            betaDirect: .init(1.2, 0.6, 0.4), betaBackscatter: .init(1.2, 1.6, 1.6), confidence: 0.8, limits: .init(),
            transmissionFloorPixelPercentage: 0, maximumGainPixelPercentage: 0)
        let auto = SubjectMask(width: 2, height: 2, values: [1, 0, 0, 0])
        plan.subjectMask = auto
        XCTAssertEqual(PhotoProcessor.applying(.auto, to: plan)?.subjectMask, auto, "the default call leaves the plan as it was")
        let picked = SubjectMask(width: 2, height: 2, values: [0, 0, 0, 1])
        XCTAssertEqual(PhotoProcessor.applying(.picked(picked), to: plan)?.subjectMask, picked)
        XCTAssertNil(PhotoProcessor.applying(.picked(nil), to: plan)?.subjectMask)
        XCTAssertNil(PhotoProcessor.applying(.picked(picked), to: nil), "no plan: the current correction runs, nothing to apply")
    }
}
