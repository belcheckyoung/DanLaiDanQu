import Foundation

/// 解析用户粘贴的 B 站链接 / BV 号 / av 号
enum BiliLink {
    case bvid(String, page: Int)
    case avid(Int64, page: Int)

    static func parse(_ input: String) -> BiliLink? {
        let s = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return nil }

        var page = 1
        if let comps = URLComponents(string: s),
           let p = comps.queryItems?.first(where: { $0.name == "p" })?.value,
           let n = Int(p), n >= 1 {
            page = n
        }

        if let r = s.range(of: #"BV[0-9A-Za-z]{10}"#, options: .regularExpression) {
            return .bvid(String(s[r]), page: page)
        }
        if let r = s.range(of: #"(?:av|AV)(\d+)"#, options: .regularExpression) {
            let digits = s[r].dropFirst(2)
            if let aid = Int64(digits) { return .avid(aid, page: page) }
        }
        return nil
    }

    /// b23.tv 等短链需要先跟随重定向再解析
    static func isShortLink(_ input: String) -> Bool {
        input.contains("b23.tv/")
    }
}
