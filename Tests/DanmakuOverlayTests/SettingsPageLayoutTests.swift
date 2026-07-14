import AppKit
import XCTest
@testable import DanmakuOverlay

final class SettingsPageLayoutTests: XCTestCase {
    @MainActor
    func testSettingsPageCoversMainContentAndReturnsWithoutSheetBorder() throws {
        let controller = MainWindowController()
        let window = try XCTUnwrap(controller.window)
        let content = try XCTUnwrap(window.contentView)
        window.setContentSize(NSSize(width: 600, height: 640))

        controller.openSettingsSheet()
        window.layoutIfNeeded()
        content.layoutSubtreeIfNeeded()

        let page = try XCTUnwrap(content.subviews.compactMap { $0 as? DisplaySettingsPage }.first)
        XCTAssertFalse(page.isHidden)
        XCTAssertEqual(page.frame.minX, content.bounds.minX, accuracy: 0.5)
        XCTAssertEqual(page.frame.minY, content.bounds.minY, accuracy: 0.5)
        XCTAssertEqual(page.frame.width, content.bounds.width, accuracy: 0.5)
        XCTAssertEqual(page.frame.height, content.bounds.height, accuracy: 0.5)
        XCTAssertTrue(window.sheets.isEmpty)

        let buttons = descendants(of: page, as: NSButton.self)
        XCTAssertNotNil(buttons.first { $0.title == "返回" })
        let saveButton = try XCTUnwrap(buttons.first { $0.title == "保存设置" })
        XCTAssertTrue(descendants(of: page, as: NSTextField.self).contains {
            $0.stringValue == "显示与屏蔽设置"
        })

        let mainScroll = try XCTUnwrap(content.subviews.compactMap { $0 as? NSScrollView }.first)
        XCTAssertTrue(mainScroll.isHidden)

        saveButton.performClick(nil)

        XCTAssertTrue(page.isHidden)
        XCTAssertFalse(mainScroll.isHidden)
        window.close()
    }

    private func descendants<T: NSView>(of root: NSView, as type: T.Type) -> [T] {
        root.subviews.flatMap { child in
            ((child as? T).map { [$0] } ?? []) + descendants(of: child, as: type)
        }
    }
}
