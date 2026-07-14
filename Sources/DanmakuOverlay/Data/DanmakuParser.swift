import Foundation

enum DanmakuParseError: LocalizedError {
    case invalidXML(String)

    var errorDescription: String? {
        switch self {
        case .invalidXML(let message):
            return "弹幕 XML 解析失败：\(message)"
        }
    }
}

/// 解析 B 站弹幕 XML（<d p="time,mode,fontsize,color,timestamp,pool,userhash,rowid">text</d>）
enum DanmakuParser {

    static func parseXML(_ data: Data) throws -> [Danmaku] {
        let delegate = XMLDelegate()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        guard parser.parse() else {
            throw DanmakuParseError.invalidXML(parser.parserError?.localizedDescription ?? "文件格式无效")
        }
        return delegate.result.sorted { $0.time < $1.time }
    }

    static func parseXMLFile(at url: URL) throws -> [Danmaku] {
        let data = try Data(contentsOf: url)
        return try parseXML(BilibiliClient.inflateIfNeeded(data))
    }

    private final class XMLDelegate: NSObject, XMLParserDelegate {
        var result: [Danmaku] = []
        private var currentAttr: String?
        private var currentText = ""

        func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?,
                    qualifiedName: String?, attributes: [String: String]) {
            if name == "d" {
                currentAttr = attributes["p"]
                currentText = ""
            }
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) {
            if currentAttr != nil { currentText += string }
        }

        func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?,
                    qualifiedName: String?) {
            guard name == "d", let attr = currentAttr else { return }
            currentAttr = nil

            let parts = attr.split(separator: ",", omittingEmptySubsequences: false)
            guard parts.count >= 8,
                  let time = Double(parts[0]),
                  let mode = Int(parts[1]) else { return }

            let text = currentText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return }

            result.append(Danmaku(
                id: String(parts[7]),
                time: time,
                mode: DanmakuMode(biliMode: mode),
                text: text,
                color: UInt32(parts[3]) ?? 0xFFFFFF,
                fontSize: Int(parts[2]) ?? 25,
                timestamp: Int(parts[4]) ?? 0,
                weight: 1
            ))
        }
    }
}
