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

    func testSmallestLimitIsFixedAtFourKAndScales() {
        XCTAssertEqual(VideoExporter.minimumLimitMB(for: CGSize(width: 3840, height: 2160)), 768)
        XCTAssertEqual(VideoExporter.minimumLimitMB(for: CGSize(width: 2160, height: 3840)), 768)
        XCTAssertEqual(VideoExporter.minimumLimitMB(for: CGSize(width: 1920, height: 1080)), 192)
    }

    func testCoreImageMemoryLimitOnlyForLargeOutputs() {
        let plenty: UInt64 = 8 << 30
        XCTAssertNil(VideoExporter.memoryLimitMB(for: CGSize(width: 1280, height: 720), availableBytes: plenty))
        XCTAssertNil(VideoExporter.memoryLimitMB(for: CGSize(width: 1920, height: 1080), availableBytes: plenty))
        XCTAssertEqual(VideoExporter.memoryLimitMB(for: CGSize(width: 3840, height: 2160), availableBytes: plenty), 1029)
    }

    #if os(iOS)
    func testIPhoneLimitFollowsFreeMemoryButNeverDropsBelowTheSmallestLimit() {
        let fourK = CGSize(width: 3840, height: 2160)
        XCTAssertEqual(VideoExporter.memoryLimitMB(for: fourK, availableBytes: 1400 << 20), 888)
        XCTAssertEqual(VideoExporter.memoryLimitMB(for: fourK, availableBytes: 1300 << 20), 788)
        // Below what a start needs, the limit stays at the smallest one (the pop-up stops the start before this).
        XCTAssertEqual(VideoExporter.memoryLimitMB(for: fourK, availableBytes: 1000 << 20), 768)
        XCTAssertEqual(VideoExporter.memoryLimitMB(for: fourK, availableBytes: 300 << 20), 768)
    }

    func testAnExportThatPassesTheMemoryCheckGetsAtLeastTheSmallestLimit() {
        for size in [CGSize(width: 3840, height: 2160), CGSize(width: 2160, height: 3840), CGSize(width: 3000, height: 1688)] {
            for freeMB in stride(from: 900, through: 4000, by: 25) {
                let free = UInt64(freeMB) << 20
                guard VideoExporter.memoryShortage(outputSize: size, availableMB: freeMB) == nil else { continue }
                let limit = VideoExporter.memoryLimitMB(for: size, availableBytes: free)
                XCTAssertGreaterThanOrEqual(limit ?? 0, VideoExporter.minimumLimitMB(for: size), "\(size) with \(freeMB) MB free")
            }
        }
    }
    #endif

    func testMacLimitDoesNotDependOnFreeMemory() {
        #if !os(iOS)
        let fourK = CGSize(width: 3840, height: 2160)
        XCTAssertEqual(VideoExporter.memoryLimitMB(for: fourK, availableBytes: 500 << 20), VideoExporter.memoryLimitMB(for: fourK, availableBytes: 8 << 30))
        #endif
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
}
