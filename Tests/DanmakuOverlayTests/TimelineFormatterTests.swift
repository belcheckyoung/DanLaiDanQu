import XCTest
@testable import DanmakuOverlay

final class TimelineFormatterTests: XCTestCase {
    func testDropsFractionalSeconds() {
        XCTAssertEqual(TimelineFormatter.string(from: 29 * 60 + 39.8), "29:39")
    }

    func testUsesMinutesAndSecondsBelowOneHour() {
        XCTAssertEqual(TimelineFormatter.string(from: 3_599.9), "59:59")
    }

    func testUsesHoursMinutesAndSecondsAtOneHour() {
        XCTAssertEqual(TimelineFormatter.string(from: 3_600), "1:00:00")
        XCTAssertEqual(TimelineFormatter.string(from: 2 * 3_600 + 30), "2:00:30")
    }

    func testClampsInvalidAndNegativeValues() {
        XCTAssertEqual(TimelineFormatter.string(from: -1), "00:00")
        XCTAssertEqual(TimelineFormatter.string(from: .infinity), "00:00")
    }
}
