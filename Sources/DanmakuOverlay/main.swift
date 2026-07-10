import AppKit

// 命令行自检：DanmakuOverlay --test-fetch <链接>，不启动 GUI
if let idx = CommandLine.arguments.firstIndex(of: "--test-fetch"),
   CommandLine.arguments.count > idx + 1 {
    let input = CommandLine.arguments[idx + 1]
    let semaphore = DispatchSemaphore(value: 0)
    Task {
        do {
            var text = input
            if BiliLink.isShortLink(text) {
                text = try await BilibiliClient.shared.resolveShortLink(text)
            }
            guard let link = BiliLink.parse(text) else {
                print("FAIL: 无法解析链接"); exit(1)
            }
            let info = try await BilibiliClient.shared.fetchVideoInfo(link: link)
            print("标题: \(info.title)")
            print("UP主: \(info.owner)  时长: \(info.duration)s  分P: \(info.pages.count)  弹幕数: \(info.danmakuCount)")
            guard let page = info.pages.first else { print("FAIL: 无分P"); exit(1) }
            let danmaku = try await BilibiliClient.shared.fetchDanmaku(cid: page.cid)
            print("实际获取弹幕: \(danmaku.count) 条")
            for d in danmaku.prefix(5) {
                print(String(format: "  [%7.2fs] %@ %@", d.time, d.mode.rawValue, d.text))
            }
            semaphore.signal()
        } catch {
            print("FAIL: \(error.localizedDescription)")
            exit(1)
        }
    }
    semaphore.wait()
    exit(0)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
