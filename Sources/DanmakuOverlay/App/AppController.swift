import AppKit

/// 应用核心状态与动作：串联数据层、时间层、渲染层、显示层
final class AppController {
    static let shared = AppController()

    private(set) var videoInfo: VideoInfo?
    private(set) var currentPage: VideoPage?
    private(set) var rawDanmaku: [Danmaku] = []      // 未过滤原始数据
    private(set) var overlayWindow: OverlayWindow?

    let hotkeys = HotkeyManager()
    private let settings = SettingsStore.shared

    var onStateChange: (() -> Void)?   // 主窗口刷新回调

    var clock: PlaybackClock? { overlayWindow?.renderView.clock }

    private init() {
        hotkeys.handler = { [weak self] action in self?.handleHotkey(action) }
        settings.onChange = { [weak self] in self?.applyFilters() }
        hotkeys.register()   // 启动即注册，⌘⇧H 可随时打开/关闭弹幕层
    }

    // MARK: - 加载流程

    func loadLink(_ input: String) async throws {
        var text = input
        if BiliLink.isShortLink(text) {
            text = try await BilibiliClient.shared.resolveShortLink(text)
        }
        guard let link = BiliLink.parse(text) else { throw BiliError.invalidLink }

        let info = try await BilibiliClient.shared.fetchVideoInfo(link: link)
        guard !info.pages.isEmpty else { throw BiliError.parseFailed }

        var pageNum = 1
        if case .bvid(_, let p) = link { pageNum = p }
        if case .avid(_, let p) = link { pageNum = p }
        let page = info.pages.first { $0.page == pageNum } ?? info.pages[0]

        await MainActor.run {
            self.videoInfo = info
            self.currentPage = page
            self.onStateChange?()
        }
        try await loadDanmaku(page: page, forceRefresh: false)
    }

    func selectPage(_ page: VideoPage) async throws {
        await MainActor.run {
            self.currentPage = page
            self.onStateChange?()
        }
        try await loadDanmaku(page: page, forceRefresh: false)
    }

    func loadDanmaku(page: VideoPage, forceRefresh: Bool) async throws {
        let list: [Danmaku]
        if !forceRefresh, let cached = Database.shared.loadDanmakuCache(cid: page.cid) {
            list = cached
        } else {
            list = try await BilibiliClient.shared.fetchDanmaku(cid: page.cid)
            Database.shared.saveDanmakuCache(cid: page.cid, list: list)
        }
        await MainActor.run {
            self.rawDanmaku = list
            if let info = self.videoInfo {
                Database.shared.recordVideo(info: info, page: page)
            }
            self.applyFilters()
            self.restoreSyncProfile()
            self.onStateChange?()
        }
    }

    /// 导入本地 XML 弹幕（兜底方案，B 站接口不可用时仍能工作）
    func importXML(from url: URL) throws {
        let list = try DanmakuParser.parseXMLFile(at: url)
        rawDanmaku = list
        videoInfo = VideoInfo(bvid: "本地文件", aid: 0,
                              title: url.deletingPathExtension().lastPathComponent,
                              owner: "本地导入", duration: 0,
                              pages: [VideoPage(cid: 0, page: 1, title: "本地弹幕", duration: 0)],
                              danmakuCount: list.count)
        currentPage = videoInfo?.pages.first
        applyFilters()
        onStateChange?()
    }

    private func applyFilters() {
        var list = FilterEngine.apply(rawDanmaku, rules: settings.rules)
        if settings.maxPerSecond > 0 {
            list = FilterEngine.downsample(list, maxPerSecond: settings.maxPerSecond)
        }
        overlayWindow?.renderView.load(danmaku: list)
    }

    // MARK: - 弹幕层

    func toggleOverlay() {
        if let w = overlayWindow, w.isVisible {
            closeOverlay()
        } else {
            openOverlay()
        }
        onStateChange?()
    }

    func openOverlay() {
        let window: OverlayWindow
        if let w = overlayWindow {
            window = w
        } else {
            window = OverlayWindow()
            overlayWindow = window
        }
        window.mousePassthrough = settings.mousePassthrough
        window.ensureOnVisibleScreen()
        window.orderFrontRegardless()
        window.renderView.startRendering()
        applyFilters()
        restoreSyncProfile()
        hotkeys.register()
        onStateChange?()
    }

    /// 暂停并记录位置（历史记录「继续看」依赖这里的自动保存）
    func pausePlayback() {
        clock?.pause()
        saveSyncProfile()
        onStateChange?()
    }

    func closeOverlay() {
        guard let w = overlayWindow else { return }
        saveSyncProfile()
        w.saveFrame()
        w.renderView.stopRendering()
        w.orderOut(nil)
        onStateChange?()
    }

    // MARK: - 倒计时启动（给用户 5 秒切到播放器点播放）

    private var countdownTimer: Timer?
    private(set) var countdownRemaining = 0
    var isCountingDown: Bool { countdownTimer != nil }

    /// thenSync = true：倒计时结束后从 0 秒开始；false：从当前时间继续播放
    func startCountdown(seconds: Int = 5, thenSync: Bool) {
        cancelCountdown()
        // 播放意味着需要弹幕层，未打开时自动打开
        if overlayWindow?.isVisible != true { openOverlay() }
        clock?.pause()
        countdownRemaining = seconds
        overlayWindow?.renderView.showCountdown(countdownRemaining)
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.countdownRemaining -= 1
            if self.countdownRemaining <= 0 {
                self.countdownTimer?.invalidate()
                self.countdownTimer = nil
                self.overlayWindow?.renderView.showCountdown(nil)
                if thenSync { self.syncFromNow() } else { self.clock?.play() }
            } else {
                self.overlayWindow?.renderView.showCountdown(self.countdownRemaining)
            }
            self.onStateChange?()
        }
        RunLoop.main.add(timer, forMode: .common)
        countdownTimer = timer
        onStateChange?()
    }

    func cancelCountdown() {
        countdownTimer?.invalidate()
        countdownTimer = nil
        countdownRemaining = 0
        overlayWindow?.renderView.showCountdown(nil)
        onStateChange?()
    }

    // MARK: - 时间轴

    func syncFromNow() {
        clock?.syncFromNow()
        overlayWindow?.renderView.resync()
        onStateChange?()
    }

    /// 跳转到绝对时间并重建屏上弹幕（进度条拖动、快进后退共用）
    func seek(to time: Double) {
        clock?.seek(to: time)
        overlayWindow?.renderView.resync()
        onStateChange?()
    }

    func adjustTime(by delta: Double) {
        guard let clock else { return }
        seek(to: clock.currentTime + delta)
    }

    func setRate(_ rate: Double) {
        clock?.rate = rate
        onStateChange?()
    }

    func saveSyncProfile() {
        guard let page = currentPage, let clock else { return }
        Database.shared.saveSyncProfile(cid: page.cid, offset: clock.currentTime, rate: clock.rate)
    }

    private func restoreSyncProfile() {
        guard let page = currentPage, let clock,
              let profile = Database.shared.loadSyncProfile(cid: page.cid) else { return }
        clock.rate = profile.rate
        // 钳制到时长内：曾保存过超出片尾的位置会导致时间轴停在结尾之后，弹幕永不出现
        var offset = max(profile.offset, 0)
        if page.duration > 0 {
            offset = min(offset, Double(page.duration) - 1)
        }
        clock.seek(to: offset)
        overlayWindow?.renderView.resync()
    }

    // MARK: - 快捷键

    private func handleHotkey(_ action: HotkeyManager.Action) {
        switch action {
        case .togglePlay:
            if clock?.isPlaying == true { pausePlayback() } else { clock?.play() }
        case .back1: adjustTime(by: -1)
        case .forward1: adjustTime(by: 1)
        case .forward5: adjustTime(by: 5)
        case .back5: adjustTime(by: -5)
        case .setZero: syncFromNow()
        case .toggleOverlay: toggleOverlay()
        }
        onStateChange?()
    }

    // MARK: - 导出

    func export(format: String, to url: URL) throws {
        let list = FilterEngine.apply(rawDanmaku, rules: settings.rules)
        let data: Data
        switch format {
        case "json": data = try DanmakuExporter.exportJSON(list)
        case "xml": data = DanmakuExporter.exportXML(list, cid: currentPage?.cid ?? 0)
        case "ass": data = DanmakuExporter.exportASS(list, title: videoInfo?.title ?? "Danmaku")
        default: return
        }
        try data.write(to: url)
    }
}
