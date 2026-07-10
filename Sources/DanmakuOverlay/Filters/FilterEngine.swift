import Foundation

/// 弹幕屏蔽（需求文档 5.1.6 节：关键词 / 正则 / 颜色 / 长度 / 重复）
struct FilterRules {
    var keywords: [String] = []
    var regexPatterns: [String] = []
    var blockColored = false          // 屏蔽彩色弹幕（只留白色）
    var maxLength: Int = 0            // 0 表示不限制
    var mergeDuplicates = true        // 合并重复内容
    var showTop = true
    var showBottom = true
    var duplicateWindow: Double = 20  // 重复判定时间窗（秒）
}

enum FilterEngine {

    static func apply(_ list: [Danmaku], rules: FilterRules) -> [Danmaku] {
        let regexes = rules.regexPatterns.compactMap {
            try? NSRegularExpression(pattern: $0)
        }
        let keywords = rules.keywords.filter { !$0.isEmpty }

        var lastSeen: [String: Double] = [:]   // 文本 -> 上次出现时间
        var result: [Danmaku] = []
        result.reserveCapacity(list.count)

        for d in list {
            if d.mode == .other { continue }
            if !rules.showTop && d.mode == .top { continue }
            if !rules.showBottom && d.mode == .bottom { continue }
            if rules.blockColored && d.color != 0xFFFFFF { continue }
            if rules.maxLength > 0 && d.text.count > rules.maxLength { continue }
            if keywords.contains(where: { d.text.localizedCaseInsensitiveContains($0) }) { continue }

            if !regexes.isEmpty {
                let range = NSRange(d.text.startIndex..., in: d.text)
                if regexes.contains(where: { $0.firstMatch(in: d.text, range: range) != nil }) { continue }
            }

            if rules.mergeDuplicates {
                if let last = lastSeen[d.text], d.time - last < rules.duplicateWindow { continue }
                lastSeen[d.text] = d.time
            }

            result.append(d)
        }
        return result
    }

    /// 高密度降采样：每秒最多保留 maxPerSecond 条（按权重优先，此处按顺序截断）
    static func downsample(_ list: [Danmaku], maxPerSecond: Int) -> [Danmaku] {
        guard maxPerSecond > 0 else { return list }
        var counts: [Int: Int] = [:]
        return list.filter { d in
            let bucket = Int(d.time)
            let c = counts[bucket, default: 0]
            if c >= maxPerSecond { return false }
            counts[bucket] = c + 1
            return true
        }
    }
}
