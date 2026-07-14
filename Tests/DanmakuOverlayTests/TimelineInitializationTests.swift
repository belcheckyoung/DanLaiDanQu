import XCTest
@testable import DanmakuOverlay

final class TimelineInitializationTests: XCTestCase {
    func testChangingRateWhilePlayingDoesNotJumpTimeline() {
        var now = Date(timeIntervalSince1970: 1_000)
        let clock = PlaybackClock(now: { now })
        clock.seek(to: 10)
        clock.play()
        now = now.addingTimeInterval(5)

        XCTAssertEqual(clock.currentTime, 15, accuracy: 0.001)
        clock.rate = 2
        XCTAssertEqual(clock.currentTime, 15, accuracy: 0.001)

        now = now.addingTimeInterval(2)
        XCTAssertEqual(clock.currentTime, 19, accuracy: 0.001)
    }

    func testSeekWorksBeforeOverlayWindowIsCreated() {
        let clock = PlaybackClock()
        let controller = AppController(clock: clock, registerHotkeys: false)

        XCTAssertNil(controller.overlayWindow)

        controller.seek(to: 123.4)

        XCTAssertTrue(controller.clock === clock)
        XCTAssertEqual(controller.clock.currentTime, 123.4, accuracy: 0.001)
        XCTAssertNil(controller.overlayWindow)
    }

    func testSeekClampsNegativeTimeBeforeOverlayWindowIsCreated() {
        let controller = AppController(clock: PlaybackClock(), registerHotkeys: false)

        controller.seek(to: -10)

        XCTAssertEqual(controller.clock.currentTime, 0, accuracy: 0.001)
    }

    func testRenderViewKeepsTimelinePositionFromBeforeItWasCreated() {
        let clock = PlaybackClock()
        clock.seek(to: 321.5)

        let renderView = DanmakuRenderView(clock: clock)

        XCTAssertTrue(renderView.clock === clock)
        XCTAssertEqual(renderView.clock.currentTime, 321.5, accuracy: 0.001)
    }
}
