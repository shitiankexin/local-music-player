import XCTest
@testable import LocalFLACPlayer

final class LRCParserTests: XCTestCase {
    func testMultipleTimeCodesAndOffset() {
        let file = LRCFile.parse("""
            [offset:+200]
            [ar:Artist]
            [00:01.50][00:03.500]第一句
            [00:05.00]第二句
            """)
        XCTAssertEqual(file.lines.count, 3)
        XCTAssertEqual(file.lines.map(\.time), [1.5, 3.5, 5.0])
        XCTAssertEqual(file.embeddedOffset, 0.2, accuracy: 0.0001)
        XCTAssertNil(file.activeIndex(at: 1.6, manualOffset: 0))
        XCTAssertEqual(file.activeIndex(at: 1.7, manualOffset: 0), 0)
        XCTAssertEqual(file.activeIndex(at: 5.3, manualOffset: 0), 2)
    }

    func testOffsetPositiveMeansLater() {
        let file = LRCFile.parse("[00:04.00]歌词")
        XCTAssertNil(file.activeIndex(at: 4.2, manualOffset: 0.5))
        XCTAssertEqual(file.activeIndex(at: 4.5, manualOffset: 0.5), 0)
    }
}
