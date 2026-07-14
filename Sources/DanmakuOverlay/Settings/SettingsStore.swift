import Foundation
import CoreGraphics

/// 全局显示设置（需求文档 5.1.5 / 7.6 节），持久化到 SQLite settings 表
final class SettingsStore {
    static let shared = SettingsStore()

    var fontSize: CGFloat { didSet { save("fontSize", "\(fontSize)") } }
    var fontName: String { didSet { save("fontName", fontName) } }
    var opacity: Double { didSet { save("opacity", "\(opacity)") } }          // 0.1 - 1.0
    var scrollDuration: Double { didSet { save("scrollDuration", "\(scrollDuration)") } }  // 弹幕横穿屏幕秒数
    var displayAreaRatio: Double { didSet { save("displayAreaRatio", "\(displayAreaRatio)") } } // 顶部起显示区域比例
    var maxPerSecond: Int { didSet { save("maxPerSecond", "\(maxPerSecond)") } }  // 0 = 不限
    var laneSpacing: CGFloat { didSet { save("laneSpacing", "\(laneSpacing)") } }
    var mousePassthrough: Bool { didSet { save("mousePassthrough", mousePassthrough ? "1" : "0") } }
    var delayedStart: Bool { didSet { save("delayedStart", delayedStart ? "1" : "0") } }  // 播放前 5 秒倒计时

    var rules = FilterRules() {
        didSet {
            db.setSetting("keywords", rules.keywords.joined(separator: "\n"))
            db.setSetting("regexPatterns", rules.regexPatterns.joined(separator: "\n"))
            db.setSetting("showTop", rules.showTop ? "1" : "0")
            db.setSetting("showBottom", rules.showBottom ? "1" : "0")
            db.setSetting("blockColored", rules.blockColored ? "1" : "0")
            db.setSetting("mergeDuplicates", rules.mergeDuplicates ? "1" : "0")
            onChange?()
        }
    }

    var onChange: (() -> Void)?

    private let db = Database.shared

    private init() {
        func str(_ key: String) -> String? { Database.shared.getSetting(key) }
        fontSize = str("fontSize").flatMap { Double($0) }.map { CGFloat($0) } ?? 28
        fontName = str("fontName") ?? "PingFang SC"
        opacity = str("opacity").flatMap { Double($0) } ?? 0.9
        scrollDuration = str("scrollDuration").flatMap { Double($0) } ?? 12
        displayAreaRatio = str("displayAreaRatio").flatMap { Double($0) } ?? 1.0
        maxPerSecond = str("maxPerSecond").flatMap { Int($0) } ?? 0
        laneSpacing = str("laneSpacing").flatMap { Double($0) }.map { CGFloat($0) } ?? 4
        mousePassthrough = str("mousePassthrough") != "0"
        delayedStart = str("delayedStart") != "0"

        var r = FilterRules()
        if let kw = str("keywords"), !kw.isEmpty {
            r.keywords = kw.components(separatedBy: "\n").filter { !$0.isEmpty }
        }
        if let regexes = str("regexPatterns"), !regexes.isEmpty {
            r.regexPatterns = regexes.components(separatedBy: "\n").filter { !$0.isEmpty }
        }
        r.showTop = str("showTop") != "0"
        r.showBottom = str("showBottom") != "0"
        r.blockColored = str("blockColored") == "1"
        r.mergeDuplicates = str("mergeDuplicates") != "0"
        rules = r
    }

    private func save(_ key: String, _ value: String) {
        db.setSetting(key, value)
        onChange?()
    }
}
