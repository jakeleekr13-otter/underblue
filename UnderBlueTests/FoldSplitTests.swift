import XCTest
@testable import UnderBlue

final class FoldSplitTests: XCTestCase {
    private let screen = CGSize(width: 466, height: 600)

    func testFoldAcrossTheScreenStacksPreviewAboveControls() throws {
        let fold = try XCTUnwrap(FoldSplit(division: CGRect(x: 0, y: 300, width: 466, height: 20), in: screen))
        XCTAssertEqual(fold, FoldSplit(division: CGRect(x: 0, y: 300, width: 466, height: 20), in: screen))
        XCTAssertEqual(fold.axis, .vertical)
        XCTAssertEqual(fold.first, 300)
        XCTAssertEqual(fold.gap, 20)
        XCTAssertEqual(fold.second, 280)
        XCTAssertEqual(fold.first + fold.gap + fold.second, screen.height)
    }

    func testFoldDownTheScreenPutsPanesSideBySide() throws {
        let fold = try XCTUnwrap(FoldSplit(division: CGRect(x: 230, y: 0, width: 12, height: 600), in: screen))
        XCTAssertEqual(fold.axis, .horizontal)
        XCTAssertEqual(fold.first, 230)
        XCTAssertEqual(fold.gap, 12)
        XCTAssertEqual(fold.second, 224)
        XCTAssertEqual(fold.first + fold.gap + fold.second, screen.width)
    }

    func testFoldNearAnEdgeIsIgnored() {
        XCTAssertNil(FoldSplit(division: CGRect(x: 0, y: 40, width: 466, height: 20), in: screen))
        XCTAssertNil(FoldSplit(division: CGRect(x: 0, y: 560, width: 466, height: 20), in: screen))
    }

    func testEmptyOrMissingFoldIsIgnored() {
        XCTAssertNil(FoldSplit(division: .zero, in: screen))
        XCTAssertNil(FoldSplit(division: .null, in: screen))
        XCTAssertNil(FoldSplit(division: CGRect(x: 0, y: 300, width: 466, height: 20), in: .zero))
    }
}
