import Foundation

/// 弹幕类型
enum DanmakuMode: String, Codable {
    case scroll   // 滚动弹幕（B 站 mode 1/2/3）
    case top      // 顶部固定（mode 5）
    case bottom   // 底部固定（mode 4）
    case other    // 高级/代码/BAS 弹幕，MVP 不渲染

    init(biliMode: Int) {
        switch biliMode {
        case 1, 2, 3: self = .scroll
        case 4: self = .bottom
        case 5: self = .top
        default: self = .other
        }
    }
}

/// 统一弹幕格式（对应需求文档 10.4 节）
struct Danmaku: Codable {
    var id: String
    var time: Double          // 出现时间（秒）
    var mode: DanmakuMode
    var text: String
    var color: UInt32         // RGB，如 0xFFFFFF
    var fontSize: Int         // B 站原始字号（25 为标准）
    var timestamp: Int        // 发送时间（Unix 秒）
    var weight: Int           // 权重/屏蔽等级

    var colorHex: String {
        String(format: "#%06X", color & 0xFFFFFF)
    }
}

/// B 站视频分 P 信息
struct VideoPage {
    var cid: Int64
    var page: Int
    var title: String
    var duration: Int   // 秒
}

/// B 站视频信息
struct VideoInfo {
    var bvid: String
    var aid: Int64
    var title: String
    var owner: String
    var duration: Int
    var pages: [VideoPage]
    var danmakuCount: Int
}
