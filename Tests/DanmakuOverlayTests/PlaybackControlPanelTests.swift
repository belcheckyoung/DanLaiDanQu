import AppKit
import XCTest
@testable import DanmakuOverlay

final class PlaybackControlPanelTests: XCTestCase {
    private final class Target: NSObject {
        @objc func action() {}
    }

    @MainActor
    func testSynchronizeProgressReplacesPreviousEpisodeRangeAndPosition() throws {
        let panel = makePanel()
        let slider = try XCTUnwrap(descendants(of: panel, as: NSSlider.self).first)

        panel.synchronizeProgress(currentTime: 1_800, duration: 3_600)
        XCTAssertEqual(slider.doubleValue, 1_800, accuracy: 0.001)
        XCTAssertEqual(slider.maxValue, 3_600, accuracy: 0.001)

        panel.synchronizeProgress(currentTime: 13, duration: 4_433)
        XCTAssertEqual(slider.doubleValue, 13, accuracy: 0.001)
        XCTAssertEqual(slider.maxValue, 4_433, accuracy: 0.001)
        XCTAssertEqual(panel.durationLabel.stringValue, "00:13 / 1:13:53")
    }

    @MainActor
    func testSynchronizeProgressClearsSliderWhenContentHasNoDuration() throws {
        let panel = makePanel()
        let slider = try XCTUnwrap(descendants(of: panel, as: NSSlider.self).first)

        panel.synchronizeProgress(currentTime: 500, duration: 0)

        XCTAssertEqual(slider.doubleValue, 0, accuracy: 0.001)
        XCTAssertFalse(slider.isEnabled)
    }

    @MainActor
    private func makePanel() -> PlaybackControlPanel {
        let target = Target()
        let action = #selector(Target.action)
        return PlaybackControlPanel(target: target, actions: .init(
            toggleOverlay: action,
            syncNow: action,
            togglePlay: action,
            delayToggled: action,
            progressDragged: action,
            back5: action,
            back1: action,
            applyOffset: action,
            forward1: action,
            forward5: action,
            saveProfile: action,
            clearScreen: action,
            openSettings: action
        ))
    }

    @MainActor
    private func descendants<T: NSView>(of root: NSView, as type: T.Type) -> [T] {
        root.subviews.flatMap { child in
            ((child as? T).map { [$0] } ?? []) + descendants(of: child, as: type)
        }
    }
}
