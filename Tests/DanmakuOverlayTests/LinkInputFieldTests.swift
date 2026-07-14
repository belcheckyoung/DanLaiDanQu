import AppKit
import XCTest
@testable import DanmakuOverlay

final class LinkInputFieldTests: XCTestCase {
    @MainActor
    func testLinkInputIsSingleLineAndHorizontallyScrollable() throws {
        let controller = MainWindowController()
        let content = try XCTUnwrap(controller.window?.contentView)
        let field = try XCTUnwrap(descendants(of: content, as: NSTextField.self).first {
            $0.placeholderString == "https://www.bilibili.com/video/BV..."
        })

        XCTAssertTrue(field.usesSingleLineMode)
        XCTAssertEqual(field.maximumNumberOfLines, 1)
        XCTAssertEqual(field.lineBreakMode, .byClipping)
        XCTAssertEqual(field.cell?.wraps, false)
        XCTAssertEqual(field.cell?.isScrollable, true)

        controller.close()
    }

    @MainActor
    private func descendants<T: NSView>(of root: NSView, as type: T.Type) -> [T] {
        root.subviews.flatMap { child in
            ((child as? T).map { [$0] } ?? []) + descendants(of: child, as: type)
        }
    }
}
