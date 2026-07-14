import AppKit

/// 应用核心状态与动作：串联数据层、时间层、渲染层、显示层
final class AppController {
    static let shared = AppController()

    private(set) var videoInfo: VideoInfo?
    private(set) var currentPage: VideoPage?
    private(set) var rawDanmaku: [Danmaku] = []      // 未过滤原始数据
    private(set) var overlayWindow: OverlayWindow?

    /// 时间轴属于应用状态，而不是弹幕窗口。这样首次打开弹幕层之前也能拖动进度条。
    let clock: PlaybackClock
    let hotkeys = HotkeyManager()
    private let settings = SettingsStore.shared
    private var loadGeneration = 0

    var onStateChange: (() -> Void)?   // 主窗口刷新回调

    init(clock: PlaybackClock = PlaybackClock(), registerHotkeys: Bool = true) {
        self.clock = clock
        hotkeys.handler = { [weak self] action in self?.handleHotkey(action) }
        settings.onChange = { [weak self] in self?.applyFilters() }
        if registerHotkeys {
            hotkeys.register()   // 启动即注册，⌘⇧H 可随时打开/关闭弹幕层
        }
    }

    // MARK: - 加载流程

    func loadLink(_ input: String) async throws {
        let generation = await beginContentChange()
        var text = input
        if BiliLink.isShortLink(text) {
            text = try await BilibiliClient.shared.resolveShortLink(text)
        }
        try await ensureCurrentLoad(generation)
        guard let link = BiliLink.parse(text) else { throw BiliError.invalidLink }

        let info = try await BilibiliClient.shared.fetchVideoInfo(link: link)
        try await ensureCurrentLoad(generation)
        guard !info.pages.isEmpty else { throw BiliError.parseFailed }

        var pageNum = 1
        if case .bvid(_, let p) = link { pageNum = p }
        if case .avid(_, let p) = link { pageNum = p }
        let page = info.pages.first { $0.page == pageNum } ?? info.pages[0]
        let list = try await fetchDanmaku(page: page, forceRefresh: false)
        try await ensureCurrentLoad(generation)
        await commitLoaded(info: info, page: page, list: list)
    }

    func selectPage(_ page: VideoPage) async throws {
        guard let info = videoInfo else { throw BiliError.parseFailed }
        let generation = await beginContentChange()
        let list = try await fetchDanmaku(page: page, forceRefresh: false)
        try await ensureCurrentLoad(generation)
        await commitLoaded(info: info, page: page, list: list)
    }

    private func fetchDanmaku(page: VideoPage, forceRefresh: Bool) async throws -> [Danmaku] {
        if !forceRefresh, let cached = Database.shared.loadDanmakuCache(cid: page.cid) {
            return cached
        }

        let list = try await BilibiliClient.shared.fetchDanmaku(cid: page.cid)
        Database.shared.saveDanmakuCache(cid: page.cid, list: list)
        return list
    }

    private func beginContentChange() async -> Int {
        await MainActor.run {
            self.loadGeneration += 1
            self.cancelCountdown()
            self.saveSyncProfile()
            self.clock.pause()
            return self.loadGeneration
        }
    }

    private func ensureCurrentLoad(_ generation: Int) async throws {
        let isCurrent = await MainActor.run { self.loadGeneration == generation }
        if !isCurrent { throw CancellationError() }
    }

    private func commitLoaded(info: VideoInfo, page: VideoPage, list: [Danmaku]) async {
        await MainActor.run {
            self.videoInfo = info
            self.currentPage = page
            self.rawDanmaku = list
            Database.shared.recordVideo(info: info, page: page)
            self.applyFilters()
            self.restoreSyncProfile()
            self.onStateChange?()
        }
    }

    /// 导入本地 XML 弹幕（兜底方案，B 站接口不可用时仍能工作）
    func importXML(from url: URL) throws {
        let list = try DanmakuParser.parseXMLFile(at: url)
        loadGeneration += 1
        cancelCountdown()
        saveSyncProfile()
        clock.pause()
        let cid = Self.localCID(for: url)
        let duration = Int(ceil(list.last?.time ?? 0))
        rawDanmaku = list
        videoInfo = VideoInfo(bvid: "local-\(abs(cid))", aid: 0,
                              title: url.deletingPathExtension().lastPathComponent,
                              owner: "本地导入", duration: duration,
                              pages: [VideoPage(cid: cid, page: 1, title: "本地弹幕", duration: duration)],
                              danmakuCount: list.count)
        currentPage = videoInfo?.pages.first
        applyFilters()
        restoreSyncProfile()
        onStateChange?()
    }

    private static func localCID(for url: URL) -> Int64 {
        var hash: UInt64 = 1_469_598_103_934_665_603
        for byte in url.standardizedFileURL.path.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        let positive = max(hash & 0x7FFF_FFFF_FFFF_FFFF, 1)
        return -Int64(positive)
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
            window = OverlayWindow(clock: clock)
            overlayWindow = window
        }
        window.mousePassthrough = settings.mousePassthrough
        window.ensureOnVisibleScreen()
        window.orderFrontRegardless()
        window.renderView.startRendering()
        applyFilters()
        hotkeys.register()
        onStateChange?()
    }

    /// 暂停并记录位置（历史记录「继续看」依赖这里的自动保存）
    func pausePlayback() {
        clock.pause()
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
        clock.pause()
        countdownRemaining = seconds
        overlayWindow?.renderView.showCountdown(countdownRemaining)
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.countdownRemaining -= 1
            if self.countdownRemaining <= 0 {
                self.countdownTimer?.invalidate()
                self.countdownTimer = nil
                self.overlayWindow?.renderView.showCountdown(nil)
                if thenSync { self.syncFromNow() } else { self.clock.play() }
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
        clock.syncFromNow()
        overlayWindow?.renderView.resync()
        onStateChange?()
    }

    /// 跳转到绝对时间并重建屏上弹幕（进度条拖动、快进后退共用）
    func seek(to time: Double) {
        clock.seek(to: time)
        overlayWindow?.renderView.resync()
        onStateChange?()
    }

    func adjustTime(by delta: Double) {
        seek(to: clock.currentTime + delta)
    }

    func setRate(_ rate: Double) {
        clock.rate = rate
        onStateChange?()
    }

    func saveSyncProfile() {
        guard let page = currentPage else { return }
        Database.shared.saveSyncProfile(cid: page.cid, offset: clock.currentTime, rate: clock.rate)
    }

    private func restoreSyncProfile() {
        guard let page = currentPage else { return }
        let profile = Database.shared.loadSyncProfile(cid: page.cid)
        clock.pause()
        clock.rate = profile?.rate ?? 1.0
        // 钳制到时长内：曾保存过超出片尾的位置会导致时间轴停在结尾之后，弹幕永不出现
        var offset = max(profile?.offset ?? 0, 0)
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
            if clock.isPlaying { pausePlayback() } else { clock.play() }
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
