import XCTest
@testable import DanmakuOverlay

final class ReturnToVideoSelectionTests: XCTestCase {
    @MainActor
    func testReturningToVideoSelectionPausesAndClosesOverlay() {
        let controller = AppController(clock: PlaybackClock(), registerHotkeys: false)
        controller.openOverlay()
        controller.clock.play()

        XCTAssertTrue(controller.clock.isPlaying)
        XCTAssertEqual(controller.overlayWindow?.isVisible, true)

        controller.returnToVideoSelection()

        XCTAssertFalse(controller.clock.isPlaying)
        XCTAssertEqual(controller.overlayWindow?.isVisible, false)
    }
}
