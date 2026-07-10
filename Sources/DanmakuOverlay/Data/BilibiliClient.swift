import Foundation
import Compression

enum BiliError: LocalizedError {
    case invalidLink
    case network(String)
    case api(code: Int, message: String)
    case needPermission
    case parseFailed

    var errorDescription: String? {
        switch self {
        case .invalidLink: return "无法识别的链接，请粘贴 B 站视频链接或 BV/av 号"
        case .network(let m): return "网络请求失败：\(m)"
        case .api(let code, let m): return "B 站接口返回错误（\(code)）：\(m)"
        case .needPermission: return "该视频需要登录或权限，当前版本仅支持公开视频"
        case .parseFailed: return "数据解析失败，接口格式可能已变化"
        }
    }
}

/// B 站公开接口客户端。仅使用无需登录的公开接口，不携带任何 Cookie。
final class BilibiliClient {
    static let shared = BilibiliClient()

    private let session: URLSession

    private init() {
        let config = URLSessionConfiguration.ephemeral   // 不持久化 Cookie
        config.httpAdditionalHeaders = [
            "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0 Safari/537.36",
            "Referer": "https://www.bilibili.com/",
        ]
        config.timeoutIntervalForRequest = 15
        session = URLSession(configuration: config)
    }

    // MARK: - 视频信息

    func fetchVideoInfo(link: BiliLink) async throws -> VideoInfo {
        var comps = URLComponents(string: "https://api.bilibili.com/x/web-interface/view")!
        switch link {
        case .bvid(let id, _): comps.queryItems = [URLQueryItem(name: "bvid", value: id)]
        case .avid(let id, _): comps.queryItems = [URLQueryItem(name: "aid", value: String(id))]
        }
        let data = try await get(comps.url!)

        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let code = root["code"] as? Int else {
            throw BiliError.parseFailed
        }
        guard code == 0, let d = root["data"] as? [String: Any] else {
            let msg = root["message"] as? String ?? "未知错误"
            if code == -403 || code == -404 || code == 62002 { throw BiliError.needPermission }
            throw BiliError.api(code: code, message: msg)
        }

        let pages: [VideoPage] = ((d["pages"] as? [[String: Any]]) ?? []).compactMap { p in
            guard let cid = p["cid"] as? Int64 ?? (p["cid"] as? Int).map(Int64.init),
                  let num = p["page"] as? Int else { return nil }
            return VideoPage(cid: cid,
                             page: num,
                             title: p["part"] as? String ?? "P\(num)",
                             duration: p["duration"] as? Int ?? 0)
        }

        let stat = d["stat"] as? [String: Any]
        let owner = d["owner"] as? [String: Any]

        return VideoInfo(
            bvid: d["bvid"] as? String ?? "",
            aid: (d["aid"] as? Int64) ?? Int64(d["aid"] as? Int ?? 0),
            title: d["title"] as? String ?? "",
            owner: owner?["name"] as? String ?? "",
            duration: d["duration"] as? Int ?? 0,
            pages: pages,
            danmakuCount: stat?["danmaku"] as? Int ?? 0
        )
    }

    /// 解析 b23.tv 短链：请求一次并取最终跳转地址
    func resolveShortLink(_ urlString: String) async throws -> String {
        guard let range = urlString.range(of: #"https?://b23\.tv/\S+"#, options: .regularExpression),
              let url = URL(string: String(urlString[range])) else {
            throw BiliError.invalidLink
        }
        let (_, response) = try await session.data(from: url)
        return response.url?.absoluteString ?? urlString
    }

    // MARK: - 弹幕获取

    /// 获取实时弹幕池（XML 接口，无需登录）
    func fetchDanmaku(cid: Int64) async throws -> [Danmaku] {
        let url = URL(string: "https://api.bilibili.com/x/v1/dm/list.so?oid=\(cid)")!
        let raw = try await get(url)
        let xmlData = Self.inflateIfNeeded(raw)
        let list = DanmakuParser.parseXML(xmlData)
        if list.isEmpty && !xmlData.isEmpty {
            // 内容非空但解析不出弹幕：可能是错误响应
            if let s = String(data: xmlData, encoding: .utf8), s.contains("error") {
                throw BiliError.api(code: -1, message: "弹幕接口拒绝访问")
            }
        }
        return list
    }

    // MARK: - 内部工具

    private func get(_ url: URL) async throws -> Data {
        do {
            let (data, response) = try await session.data(from: url)
            if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                throw BiliError.network("HTTP \(http.statusCode)")
            }
            return data
        } catch let e as BiliError {
            throw e
        } catch {
            throw BiliError.network(error.localizedDescription)
        }
    }

    /// 弹幕接口返回 raw deflate（有时带 zlib 头，有时已被 URLSession 解压）
    static func inflateIfNeeded(_ data: Data) -> Data {
        guard !data.isEmpty else { return data }
        // 已是明文 XML
        if data.starts(with: Array("<?xml".utf8)) || data.first == UInt8(ascii: "<") {
            return data
        }
        // zlib 头 0x78 需跳过 2 字节；否则按 raw deflate 处理
        var payload = data
        if data.count > 2 && data[data.startIndex] == 0x78 {
            payload = data.dropFirst(2)
        }
        return inflate(payload) ?? data
    }

    private static func inflate(_ data: Data) -> Data? {
        // 缓冲不够时加倍重试（弹幕 XML 最大不过几十 MB）
        var capacity = max(data.count * 8, 1 << 20)
        for _ in 0..<8 {
            var dst = Data(count: capacity)
            let written = dst.withUnsafeMutableBytes { dstPtr in
                data.withUnsafeBytes { srcPtr in
                    compression_decode_buffer(
                        dstPtr.bindMemory(to: UInt8.self).baseAddress!, capacity,
                        srcPtr.bindMemory(to: UInt8.self).baseAddress!, data.count,
                        nil, COMPRESSION_ZLIB)
                }
            }
            if written == 0 { return nil }
            if written < capacity { return dst.prefix(written) }
            capacity *= 2
        }
        return nil
    }
}
