import Foundation

/// 导出 XML / ASS / JSON（需求文档 5.1.8 兜底导出）
enum DanmakuExporter {

    static func exportJSON(_ list: [Danmaku]) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(list)
    }

    static func exportXML(_ list: [Danmaku], cid: Int64) -> Data {
        var s = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<i>\n<chatid>\(cid)</chatid>\n"
        for d in list {
            let biliMode: Int
            switch d.mode {
            case .scroll: biliMode = 1
            case .bottom: biliMode = 4
            case .top: biliMode = 5
            case .other: biliMode = 7
            }
            let p = "\(d.time),\(biliMode),\(d.fontSize),\(d.color),\(d.timestamp),0,0,\(d.id)"
            s += "<d p=\"\(p)\">\(escapeXML(d.text))</d>\n"
        }
        s += "</i>\n"
        return Data(s.utf8)
    }

    /// 生成 ASS 字幕，可作为外挂字幕导入 Infuse/IINA 等播放器
    static func exportASS(_ list: [Danmaku],
                          title: String,
                          screenWidth: Int = 1920,
                          screenHeight: Int = 1080,
                          fontSize: Int = 48,
                          scrollDuration: Double = 12,
                          fixedDuration: Double = 5,
                          laneCount: Int = 14) -> Data {
        var s = """
        [Script Info]
        Title: \(title)
        ScriptType: v4.00+
        PlayResX: \(screenWidth)
        PlayResY: \(screenHeight)
        WrapStyle: 2
        ScaledBorderAndShadow: yes

        [V4+ Styles]
        Format: Name, Fontname, Fontsize, PrimaryColour, SecondaryColour, OutlineColour, BackColour, Bold, Italic, Underline, StrikeOut, ScaleX, ScaleY, Spacing, Angle, BorderStyle, Outline, Shadow, Alignment, MarginL, MarginR, MarginV, Encoding
        Style: Danmaku,PingFang SC,\(fontSize),&H00FFFFFF,&H00FFFFFF,&H00000000,&H00000000,0,0,0,0,100,100,0,0,1,1.5,0,7,0,0,0,1

        [Events]
        Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text

        """

        let laneHeight = screenHeight / 3 / max(laneCount / 3, 1)
        var scrollLaneFree = [Double](repeating: 0, count: laneCount)   // 车道下次可用时间
        var topLaneFree = [Double](repeating: 0, count: 5)
        var bottomLaneFree = [Double](repeating: 0, count: 5)

        for d in list where d.mode != .other {
            let colorTag = d.color == 0xFFFFFF ? "" : String(format: "{\\c&H%02X%02X%02X&}",
                                                             d.color & 0xFF, (d.color >> 8) & 0xFF, (d.color >> 16) & 0xFF)
            let text = colorTag + escapeASS(d.text)

            switch d.mode {
            case .scroll:
                guard let lane = scrollLaneFree.firstIndex(where: { $0 <= d.time }) else { continue }
                let textWidth = Double(estimateWidth(d.text, fontSize: fontSize))
                // 前一条完全离开右边缘后车道才可复用（近似）
                scrollLaneFree[lane] = d.time + scrollDuration * textWidth / (Double(screenWidth) + textWidth) + 0.3
                let y = lane * laneHeight
                let move = "{\\move(\(screenWidth + Int(textWidth) / 2),\(y),\(-Int(textWidth) / 2),\(y))}"
                s += assLine(start: d.time, end: d.time + scrollDuration, text: move + text)
            case .top:
                guard let lane = topLaneFree.firstIndex(where: { $0 <= d.time }) else { continue }
                topLaneFree[lane] = d.time + fixedDuration
                let pos = "{\\an8\\pos(\(screenWidth / 2),\(lane * laneHeight))}"
                s += assLine(start: d.time, end: d.time + fixedDuration, text: pos + text)
            case .bottom:
                guard let lane = bottomLaneFree.firstIndex(where: { $0 <= d.time }) else { continue }
                bottomLaneFree[lane] = d.time + fixedDuration
                let pos = "{\\an2\\pos(\(screenWidth / 2),\(screenHeight - 40 - lane * laneHeight))}"
                s += assLine(start: d.time, end: d.time + fixedDuration, text: pos + text)
            case .other:
                break
            }
        }
        return Data(s.utf8)
    }

    // MARK: - helpers

    private static func assLine(start: Double, end: Double, text: String) -> String {
        "Dialogue: 0,\(assTime(start)),\(assTime(end)),Danmaku,,0,0,0,,\(text)\n"
    }

    private static func assTime(_ t: Double) -> String {
        let t = max(t, 0)
        let h = Int(t) / 3600
        let m = Int(t) % 3600 / 60
        let sec = Int(t) % 60
        let cs = Int((t - t.rounded(.down)) * 100)
        return String(format: "%d:%02d:%02d.%02d", h, m, sec, cs)
    }

    private static func estimateWidth(_ text: String, fontSize: Int) -> Int {
        var w = 0.0
        for ch in text.unicodeScalars {
            w += ch.value > 0x2E80 ? 1.0 : 0.55   // CJK 全宽，其余按半宽估算
        }
        return Int(w * Double(fontSize))
    }

    private static func escapeXML(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
         .replacingOccurrences(of: "<", with: "&lt;")
         .replacingOccurrences(of: ">", with: "&gt;")
    }

    private static func escapeASS(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\")
         .replacingOccurrences(of: "{", with: "(")
         .replacingOccurrences(of: "}", with: ")")
         .replacingOccurrences(of: "\n", with: " ")
    }
}
