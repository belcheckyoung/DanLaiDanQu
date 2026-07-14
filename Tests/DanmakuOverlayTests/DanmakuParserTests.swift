import Foundation
import XCTest
@testable import DanmakuOverlay

final class DanmakuParserTests: XCTestCase {
    func testValidXMLParsesAndSortsDanmaku() throws {
        let xml = Data("""
        <?xml version="1.0"?><i>
        <d p="2,1,25,16777215,1,0,u,second">second</d>
        <d p="1,5,25,16711680,1,0,u,first">first</d>
        </i>
        """.utf8)

        let result = try DanmakuParser.parseXML(xml)

        XCTAssertEqual(result.map(\.id), ["first", "second"])
        XCTAssertEqual(result.first?.mode, .top)
    }

    func testMalformedXMLThrowsInsteadOfReportingEmptySuccess() {
        let xml = Data("<i><d p=\"1,1,25,16777215,1,0,u,id\">broken".utf8)

        XCTAssertThrowsError(try DanmakuParser.parseXML(xml))
    }
}
