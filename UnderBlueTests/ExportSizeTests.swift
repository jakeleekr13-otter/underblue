import XCTest
@testable import UnderBlue

final class ExportSizeTests: XCTestCase {
    private func size(_ width: CGFloat, _ height: CGFloat, hd: Bool = false) -> CGSize {
        var options = ExportOptions()
        options.resolution = hd ? .hd : .source
        return options.size(for: CGSize(width: width, height: height))
    }

    func testEightKExportsAtFourK() {
        XCTAssertEqual(size(7680, 4320), CGSize(width: 3840, height: 2160))
        XCTAssertEqual(size(4320, 7680), CGSize(width: 2160, height: 3840))
        XCTAssertEqual(size(5120, 2880), CGSize(width: 3840, height: 2160))
    }

    func testFourKAndSmallerStayAsTheyAre() {
        XCTAssertEqual(size(3840, 2160), CGSize(width: 3840, height: 2160))
        XCTAssertEqual(size(2160, 3840), CGSize(width: 2160, height: 3840))
        XCTAssertEqual(size(1920, 1080), CGSize(width: 1920, height: 1080))
        XCTAssertEqual(size(720, 1280), CGSize(width: 720, height: 1280))
    }

    func testCinemaFourKIsScaledToFit() {
        let result = size(4096, 2160)
        XCTAssertEqual(result.width, 3840)
        XCTAssertLessThanOrEqual(result.height, 2160)
        XCTAssertEqual(result.height.truncatingRemainder(dividingBy: 2), 0)
    }

    func testFullHDOptionStillWorksOnLargeSources() {
        XCTAssertEqual(size(7680, 4320, hd: true), CGSize(width: 1920, height: 1080))
        XCTAssertEqual(size(3840, 2160, hd: true), CGSize(width: 1920, height: 1080))
    }

    func testOnlySourcesBeyondFourKAreFlagged() {
        XCTAssertTrue(ExportOptions.exceedsSupportedSize(CGSize(width: 7680, height: 4320)))
        XCTAssertFalse(ExportOptions.exceedsSupportedSize(CGSize(width: 4096, height: 2160)))
        XCTAssertFalse(ExportOptions.exceedsSupportedSize(CGSize(width: 3840, height: 2160)))
    }

    func testBestIsFourKOutput() {
        XCTAssertTrue(ExportOptions.isBest(CGSize(width: 3840, height: 2160)))
        XCTAssertTrue(ExportOptions.isBest(CGSize(width: 7680, height: 4320)))
        XCTAssertFalse(ExportOptions.isBest(CGSize(width: 1920, height: 1080)))
    }

    func testCoreImageMemoryLimitOnlyForLargeOutputs() {
        let plenty: UInt64 = 8 << 30
        XCTAssertNil(VideoExporter.memoryLimitMB(for: CGSize(width: 1280, height: 720), availableBytes: plenty))
        XCTAssertNil(VideoExporter.memoryLimitMB(for: CGSize(width: 1920, height: 1080), availableBytes: plenty))
        XCTAssertEqual(VideoExporter.memoryLimitMB(for: CGSize(width: 3840, height: 2160), availableBytes: plenty), 1029)
    }

    func testNeededFreeMemoryGrowsWithOutputSize() {
        XCTAssertEqual(VideoExporter.requiredAvailableMB(for: CGSize(width: 3840, height: 2160)), 1300)
        XCTAssertLessThan(VideoExporter.requiredAvailableMB(for: CGSize(width: 1920, height: 1080)), 700)
    }

    func testShortageOnlyWhenFreeMemoryIsBelowWhatTheOutputNeeds() {
        let fourK = CGSize(width: 3840, height: 2160)
        XCTAssertNil(VideoExporter.memoryShortage(outputSize: fourK, availableMB: 1300))
        XCTAssertNil(VideoExporter.memoryShortage(outputSize: fourK, availableMB: 3000))
        XCTAssertEqual(VideoExporter.memoryShortage(outputSize: fourK, availableMB: 980),
                       VideoExporter.MemoryShortage(availableMB: 980, neededMB: 1300))
        // A small output still starts when the same free memory is too little for 4K.
        XCTAssertNil(VideoExporter.memoryShortage(outputSize: CGSize(width: 1920, height: 1080), availableMB: 980))
    }

    func testCoreImageMemoryLimitFollowsFreeMemory() {
        let fourK = CGSize(width: 3840, height: 2160)
        // The free memory minus the reserve, when that is below what 4K wants.
        XCTAssertEqual(VideoExporter.memoryLimitMB(for: fourK, availableBytes: 1000 << 20), 488)
        XCTAssertEqual(VideoExporter.memoryLimitMB(for: fourK, availableBytes: 1400 << 20), 888)
        // Too little free memory: keep the system default instead of a small limit.
        XCTAssertNil(VideoExporter.memoryLimitMB(for: fourK, availableBytes: 700 << 20))
    }
}
