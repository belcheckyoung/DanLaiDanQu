import AppKit

/// 主控制窗口：链接输入、视频信息、分 P 选择、同步控制、显示设置、屏蔽、导出、历史记录
final class MainWindowController: NSWindowController, NSMenuDelegate, NSMenuItemValidation {

    /// 主菜单「控制」项的可用性：没有弹幕且不在播放/倒计时中时禁用
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(togglePlay) || menuItem.action == #selector(syncNow) {
            return !controller.rawDanmaku.isEmpty
                || controller.isCountingDown
                || controller.clock?.isPlaying == true
        }
        return true
    }

    private let controller = AppController.shared
    private let settings = SettingsStore.shared

    // 输入区
    private let linkField = NSTextField()
    private let loadButton = NSButton(title: "加载弹幕", target: nil, action: nil)
    private let statusLabel = NSTextField(labelWithString: "粘贴 Bilibili 视频链接（BV / av / b23.tv）")

    // 信息区
    private let titleLabel = NSTextField(wrappingLabelWithString: "")
    private let metaLabel = NSTextField(labelWithString: "")
    private let pagePopup = NSPopUpButton()

    // 分步页面
    private var sourceCards: [NSView] = []      // 第一步：选片
    private var playbackCards: [NSView] = []    // 第二步：同步播放
    private var playbackPanel: PlaybackControlPanel!
    private var displaySettingsSheet: DisplaySettingsSheet!
    private weak var contentStack: NSStackView?
    private var rateMenuItems: [NSMenuItem] = []
    private var passthroughMenuItem: NSMenuItem?

    // 同步区
    private var lastSeekAt = Date.distantPast

    // 历史记录
    private let historyList = HistoryListView()

    private var timeTimer: Timer?

    convenience init() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 520, height: 850),
                              styleMask: [.titled, .closable, .miniaturizable],
                              backing: .buffered, defer: false)
        window.title = "弹来弹去"
        window.center()
        self.init(window: window)
        buildUI()
        bindActions()
        controller.onStateChange = { [weak self] in self?.refresh() }
        refresh()
        startTimeTimer()
    }

    // MARK: - UI 构建

    private func buildUI() {
        guard let window else { return }

        // Liquid Glass 窗口 chrome：隐藏标题栏、内容延伸到顶、磨砂穿透背景
        OverlayTheme.configureGlassWindow(window)
        window.minSize = NSSize(width: 600, height: 440)
        window.setContentSize(NSSize(width: 600, height: 640))

        let root = MainWindowUI.windowBackdrop()
        window.contentView = root
        let content = root

        linkField.placeholderString = "https://www.bilibili.com/video/BV..."
        linkField.font = .systemFont(ofSize: 13)

        titleLabel.font = .boldSystemFont(ofSize: 14)
        titleLabel.maximumNumberOfLines = 2
        metaLabel.font = .systemFont(ofSize: 12)
        metaLabel.textColor = .secondaryLabelColor
        statusLabel.font = .systemFont(ofSize: 12)
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.lineBreakMode = .byTruncatingTail

        playbackPanel = PlaybackControlPanel(target: self, actions: .init(
            toggleOverlay: #selector(toggleOverlay),
            syncNow: #selector(syncNow),
            togglePlay: #selector(togglePlay),
            delayToggled: #selector(delayToggled),
            progressDragged: #selector(progressDragged),
            back5: #selector(back5),
            back1: #selector(back1),
            applyOffset: #selector(applyOffset),
            forward1: #selector(fwd1),
            forward5: #selector(fwd5),
            saveProfile: #selector(saveProfile),
            clearScreen: #selector(clearScreen),
            openSettings: #selector(openSettingsSheet)
        ))
        playbackPanel.delayedStart = settings.delayedStart

        displaySettingsSheet = DisplaySettingsSheet(target: self, actions: .init(
            close: #selector(closeSettingsSheet),
            fontChanged: #selector(fontChanged),
            opacityChanged: #selector(opacityChanged),
            speedChanged: #selector(speedChanged),
            areaChanged: #selector(areaChanged),
            densityChanged: #selector(densityChanged),
            keywordsChanged: #selector(keywordsChanged),
            checksChanged: #selector(checksChanged)
        ))
        displaySettingsSheet.restore(from: settings)

        let inputRow = MainWindowUI.hstack(linkField, loadButton)
        linkField.setContentHuggingPriority(.defaultLow, for: .horizontal)
        loadButton.bezelStyle = .glass
        loadButton.bezelColor = OverlayTheme.accentPink.withAlphaComponent(0.45)
        loadButton.contentTintColor = .labelColor
        loadButton.image = NSImage(systemSymbolName: "arrow.down.circle.fill", accessibilityDescription: "加载弹幕")
        loadButton.imagePosition = .imageLeading

        historyList.onSelect = { [weak self] entry in
            self?.loadHistoryEntry(entry)
        }

        // 顶部标题区 + 「更多」二级菜单
        let appIcon = NSImageView(image: NSImage(systemSymbolName: "text.bubble.fill", accessibilityDescription: "弹来弹去") ?? NSImage())
        appIcon.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 26, weight: .semibold)
        appIcon.contentTintColor = OverlayTheme.accentPink
        let appTitle = NSTextField(labelWithString: "弹来弹去")
        appTitle.font = .systemFont(ofSize: 20, weight: .bold)
        // 副标题带版本号，方便分辨安装版/开发版（裸二进制运行时无 Info.plist，回退不显示）
        let version = (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String).map { " · v\($0)" } ?? ""
        let appSubtitle = NSTextField(labelWithString: "Bilibili 弹幕悬浮层\(version)")
        appSubtitle.font = .systemFont(ofSize: 11)
        appSubtitle.textColor = .secondaryLabelColor
        let titleStack = NSStackView(views: [appTitle, appSubtitle])
        titleStack.orientation = .vertical
        titleStack.alignment = .leading
        titleStack.spacing = 1

        let headerRow = NSStackView()
        headerRow.orientation = .horizontal
        headerRow.spacing = 10
        headerRow.addView(appIcon, in: .leading)
        headerRow.addView(titleStack, in: .leading)
        headerRow.addView(makeMoreButton(), in: .trailing)
        let headerBar = MainWindowUI.headerBar(headerRow)

        // 第二步「正在播放」卡片：信息 + 返回换片
        let backButton = MainWindowUI.smallButton("← 换个视频", target: self, action: #selector(backToSource))
        let playingHeader = NSStackView()
        playingHeader.orientation = .horizontal
        playingHeader.addView(MainWindowUI.sectionHeader("play.rectangle.fill", "正在播放"), in: .leading)
        playingHeader.addView(backButton, in: .trailing)

        // 两步页面的卡片
        let sourceCard = MainWindowUI.card(MainWindowUI.sectionStack([MainWindowUI.sectionHeader("link", "第一步 · 选择弹幕源"),
                                            inputRow, statusLabel]))
        let historyCard = MainWindowUI.card(MainWindowUI.sectionStack([MainWindowUI.sectionHeader("clock.arrow.circlepath", "历史记录 · 点击继续看"),
                                             historyList]))
        let playingCard = MainWindowUI.card(MainWindowUI.sectionStack([playingHeader, titleLabel, metaLabel, pagePopup]))
        let syncCard = MainWindowUI.card(playbackPanel)
        sourceCards = [sourceCard, historyCard]
        playbackCards = [playingCard, syncCard]

        let allCards = sourceCards + playbackCards
        let stack = NSStackView(views: [headerBar] + allCards)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 13
        let inset = OverlayTheme.windowContentInset
        stack.edgeInsets = NSEdgeInsets(top: 48, left: inset, bottom: 24, right: inset)
        stack.translatesAutoresizingMaskIntoConstraints = false
        headerBar.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -inset * 2).isActive = true
        for c in allCards {
            c.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -inset * 2).isActive = true
        }
        contentStack = stack
        showPage(playback: false)

        // 玻璃容器合并渲染；内容整体可滚动，窗口可自由缩放
        let container = NSGlassEffectContainerView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.contentView = stack
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: container.topAnchor),
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])

        let doc = FlippedView()
        doc.translatesAutoresizingMaskIntoConstraints = false
        doc.addSubview(container)

        let scroll = NSScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.automaticallyAdjustsContentInsets = false
        scroll.documentView = doc
        content.addSubview(scroll)

        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: content.topAnchor),
            scroll.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            doc.topAnchor.constraint(equalTo: scroll.contentView.topAnchor),
            doc.leadingAnchor.constraint(equalTo: scroll.contentView.leadingAnchor),
            doc.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor),
            container.topAnchor.constraint(equalTo: doc.topAnchor),
            container.leadingAnchor.constraint(equalTo: doc.leadingAnchor),
            container.trailingAnchor.constraint(equalTo: doc.trailingAnchor),
            container.bottomAnchor.constraint(equalTo: doc.bottomAnchor),
        ])

        window.center()
    }

    private func bindActions() {
        loadButton.target = self; loadButton.action = #selector(loadLink)
        linkField.target = self; linkField.action = #selector(loadLink)
        pagePopup.target = self; pagePopup.action = #selector(pageChanged)
    }

    // MARK: - 动作

    @objc private func loadLink() {
        let text = linkField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        linkField.stringValue = text
        statusLabel.stringValue = "加载中…"
        loadButton.isEnabled = false
        Task { @MainActor in
            do {
                try await controller.loadLink(text)
                if let page = controller.currentPage,
                   let p = Database.shared.loadSyncProfile(cid: page.cid), p.offset > 5 {
                    statusLabel.stringValue = "弹幕加载完成，已恢复到上次位置 \(mmss(p.offset))"
                } else {
                    statusLabel.stringValue = "弹幕加载完成"
                }
                showPage(playback: true)
            } catch {
                statusLabel.stringValue = error.localizedDescription
            }
            loadButton.isEnabled = true
        }
    }

    @objc private func toggleOverlay() { controller.toggleOverlay() }

    /// 从此刻同步：5 秒倒计时后弹幕从 0 秒开始，给用户时间去点视频的播放
    /// internal @objc：主菜单「控制」通过响应链调用（⌘S），两个页面都生效
    @objc func syncNow() {
        if controller.isCountingDown {
            controller.cancelCountdown()
            statusLabel.stringValue = "已取消倒计时"
        } else {
            controller.startCountdown(thenSync: true)
            statusLabel.stringValue = "倒计时结束时弹幕从 0 秒开始——请在归零瞬间点击视频播放"
        }
    }

    /// 播放/暂停：开关决定是否先倒计时 5 秒；暂停与取消倒计时永远立即生效
    /// internal @objc：主菜单「控制」通过响应链调用（⌘P），两个页面都生效
    @objc func togglePlay() {
        if controller.isCountingDown {
            controller.cancelCountdown()
            statusLabel.stringValue = "已取消倒计时"
        } else if controller.clock?.isPlaying == true {
            controller.pausePlayback()
        } else if settings.delayedStart {
            controller.startCountdown(thenSync: false)
            statusLabel.stringValue = "倒计时结束时弹幕继续播放——请在归零瞬间点击视频播放"
        } else {
            if controller.overlayWindow?.isVisible != true { controller.openOverlay() }
            controller.clock?.play()
        }
    }

    @objc private func delayToggled() {
        settings.delayedStart = playbackPanel.delayedStart
    }
    @objc private func back1() { controller.adjustTime(by: -1) }
    @objc private func fwd1() { controller.adjustTime(by: 1) }
    @objc private func back5() { controller.adjustTime(by: -5) }
    @objc private func fwd5() { controller.adjustTime(by: 5) }
    @objc private func clearScreen() { controller.overlayWindow?.renderView.clearScreen() }
    @objc private func saveProfile() {
        controller.saveSyncProfile()
        statusLabel.stringValue = "已保存当前偏移，下次打开此视频自动恢复"
    }

    @objc private func progressDragged() {
        lastSeekAt = Date()
        let t = playbackPanel.progressValue
        controller.seek(to: t)
        playbackPanel.setDraggedTime(t, playing: controller.clock?.isPlaying == true, duration: totalDuration())
    }

    @objc private func applyOffset() {
        if let value = parseOffset(playbackPanel.offsetText) {
            controller.adjustTime(by: value)
        }
        playbackPanel.offsetText = ""
    }

    @objc private func pageChanged() {
        guard let info = controller.videoInfo,
              pagePopup.indexOfSelectedItem < info.pages.count else { return }
        let page = info.pages[pagePopup.indexOfSelectedItem]
        Task { @MainActor in
            do { try await controller.selectPage(page) }
            catch { statusLabel.stringValue = error.localizedDescription }
        }
    }

    // MARK: - 分步页面与二级菜单

    private func showPage(playback: Bool) {
        for v in sourceCards { v.isHidden = playback }
        for v in playbackCards { v.isHidden = !playback }
        sizeWindowToFitPage()
    }

    /// 窗口高度贴合当前页内容，切页时动画过渡，不留大片空白
    private func sizeWindowToFitPage() {
        guard let window, let stack = contentStack else { return }
        window.layoutIfNeeded()
        let contentH = stack.fittingSize.height
        let maxH = (window.screen ?? NSScreen.main)?.visibleFrame.height ?? 900
        let newH = min(max(contentH, 320), maxH - 40)
        var frame = window.frame
        guard abs(frame.height - newH) > 2 else { return }
        frame.origin.y += frame.height - newH   // 顶边不动，向下收缩/展开
        frame.size.height = newH
        window.setFrame(frame, display: true, animate: window.isVisible)
    }

    @objc private func backToSource() {
        showPage(playback: false)
        window?.makeFirstResponder(linkField)
    }

    private func makeMoreButton() -> NSView {
        let button = NSPopUpButton()
        button.pullsDown = true
        button.isBordered = true
        button.bezelStyle = .glass
        (button.cell as? NSPopUpButtonCell)?.arrowPosition = .noArrow

        let menu = NSMenu()
        menu.delegate = self
        let face = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        face.image = NSImage(systemSymbolName: "ellipsis.circle", accessibilityDescription: "更多")?
            .withSymbolConfiguration(.init(pointSize: 17, weight: .medium))
        menu.addItem(face)

        let settingsItem = NSMenuItem(title: "显示与屏蔽设置…", action: #selector(openSettingsSheet), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)
        menu.addItem(.separator())

        let rateRoot = NSMenuItem(title: "倍速", action: nil, keyEquivalent: "")
        let rateMenu = NSMenu()
        for r in [0.5, 0.75, 1.0, 1.25, 1.5, 2.0] {
            let item = NSMenuItem(title: r == 1.0 ? "1x（正常）" : "\(r)x",
                                  action: #selector(rateMenuPicked(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = r
            rateMenu.addItem(item)
            rateMenuItems.append(item)
        }
        rateRoot.submenu = rateMenu
        menu.addItem(rateRoot)

        let pass = NSMenuItem(title: "鼠标穿透（关闭后可拖动弹幕层）", action: #selector(togglePassthroughMenu), keyEquivalent: "")
        pass.target = self
        menu.addItem(pass)
        passthroughMenuItem = pass

        for (title, sel) in [("清屏 3 秒", #selector(clearScreen)), ("保存偏移", #selector(saveProfile))] {
            let item = NSMenuItem(title: title, action: sel, keyEquivalent: "")
            item.target = self
            menu.addItem(item)
        }
        menu.addItem(.separator())
        for (title, sel) in [("导入 XML…", #selector(importXML)), ("导出 XML…", #selector(exportXML)),
                             ("导出 ASS…", #selector(exportASS)), ("导出 JSON…", #selector(exportJSON))] {
            let item = NSMenuItem(title: title, action: sel, keyEquivalent: "")
            item.target = self
            menu.addItem(item)
        }

        button.menu = menu
        return button
    }

    /// 菜单打开时同步勾选状态
    func menuWillOpen(_ menu: NSMenu) {
        passthroughMenuItem?.state = settings.mousePassthrough ? .on : .off
        let current = controller.clock?.rate ?? 1.0
        for item in rateMenuItems {
            item.state = (item.representedObject as? Double) == current ? .on : .off
        }
    }

    @objc private func rateMenuPicked(_ item: NSMenuItem) {
        if let r = item.representedObject as? Double { controller.setRate(r) }
    }

    @objc private func togglePassthroughMenu() {
        settings.mousePassthrough.toggle()
        controller.overlayWindow?.mousePassthrough = settings.mousePassthrough
        updatePlaybackStateLabels(currentTime: controller.clock?.currentTime ?? 0)
        syncWindowLevel()
    }

    /// 穿透关闭（弹幕层可交互）时，弹幕层会拦截落向主窗口的点击——
    /// 把主窗口临时抬到弹幕层之上保证软件自身可操作；恢复穿透后回到普通层级
    private func syncWindowLevel() {
        let overlayInteractive = controller.overlayWindow?.isVisible == true && !settings.mousePassthrough
        let target: NSWindow.Level = overlayInteractive
            ? NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 1)
            : .normal
        if let window, window.level != target {
            window.level = target
            if overlayInteractive { window.orderFrontRegardless() }
        }
    }

    @objc func openSettingsSheet() {
        if let window { displaySettingsSheet.beginSheet(on: window) }
    }

    @objc private func closeSettingsSheet() {
        displaySettingsSheet.endSheet(from: window)
    }

    @objc private func fontChanged() {
        settings.fontSize = displaySettingsSheet.fontSize
        displaySettingsSheet.updateValueLabels(from: settings)
    }

    @objc private func opacityChanged() {
        settings.opacity = displaySettingsSheet.opacity
        displaySettingsSheet.updateValueLabels(from: settings)
    }

    @objc private func speedChanged() {
        settings.scrollDuration = displaySettingsSheet.scrollDuration
        displaySettingsSheet.updateValueLabels(from: settings)
    }

    @objc private func areaChanged() {
        settings.displayAreaRatio = displaySettingsSheet.displayAreaRatio
        displaySettingsSheet.updateValueLabels(from: settings)
    }

    @objc private func densityChanged() {
        settings.maxPerSecond = displaySettingsSheet.maxPerSecond
    }

    @objc private func keywordsChanged() {
        settings.rules = displaySettingsSheet.rules(basedOn: settings.rules)
    }

    @objc private func checksChanged() {
        settings.rules = displaySettingsSheet.rules(basedOn: settings.rules)
    }

    // MARK: - 导入导出

    @objc private func importXML() {
        guard let window else { return }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.xml]
        panel.beginSheetModal(for: window) { [weak self] resp in
            guard resp == .OK, let url = panel.url else { return }
            do {
                try self?.controller.importXML(from: url)
                self?.statusLabel.stringValue = "本地弹幕导入成功"
                self?.showPage(playback: true)
            } catch {
                self?.statusLabel.stringValue = "导入失败：\(error.localizedDescription)"
            }
        }
    }

    @objc private func exportXML() { export(format: "xml", ext: "xml") }
    @objc private func exportASS() { export(format: "ass", ext: "ass") }
    @objc private func exportJSON() { export(format: "json", ext: "json") }

    private func export(format: String, ext: String) {
        guard !controller.rawDanmaku.isEmpty else {
            statusLabel.stringValue = "请先加载弹幕"
            return
        }
        guard let window else { return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = safeFilename(controller.videoInfo?.title ?? "danmaku", ext: ext)
        panel.beginSheetModal(for: window) { [weak self] resp in
            guard resp == .OK, let url = panel.url else { return }
            do {
                try self?.controller.export(format: format, to: url)
                self?.statusLabel.stringValue = "已导出 \(url.lastPathComponent)"
            } catch {
                self?.statusLabel.stringValue = "导出失败：\(error.localizedDescription)"
            }
        }
    }

    // MARK: - 历史记录列表

    private func loadHistoryEntry(_ e: Database.HistoryEntry) {
        linkField.stringValue = "https://www.bilibili.com/video/\(e.bvid)?p=\(e.page)"
        loadLink()
    }

    private func reloadHistory() {
        historyList.reload(entries: Database.shared.recentVideos())
    }

    // MARK: - 刷新

    private func refresh() {
        if let info = controller.videoInfo {
            titleLabel.stringValue = info.title
            let mins = info.duration / 60, secs = info.duration % 60
            metaLabel.stringValue = "\(info.owner) · \(mins)分\(secs)秒 · 弹幕 \(info.danmakuCount) 条 · 已加载 \(controller.rawDanmaku.count) 条"

            pagePopup.removeAllItems()
            for p in info.pages { pagePopup.addItem(withTitle: "P\(p.page) \(p.title)") }
            if let current = controller.currentPage,
               let idx = info.pages.firstIndex(where: { $0.cid == current.cid }) {
                pagePopup.selectItem(at: idx)
            }
            pagePopup.isHidden = info.pages.count <= 1
        } else {
            titleLabel.stringValue = ""
            metaLabel.stringValue = ""
            pagePopup.isHidden = true
        }
        titleLabel.isHidden = controller.videoInfo == nil
        metaLabel.isHidden = controller.videoInfo == nil
        let overlayVisible = controller.overlayWindow?.isVisible ?? false
        playbackPanel.setOverlayVisible(overlayVisible)
        updatePlaybackStateLabels(currentTime: controller.clock?.currentTime ?? 0)
        syncWindowLevel()
        reloadHistory()
    }

    private func startTimeTimer() {
        // 挂到 .common 模式：拖动滑块（鼠标追踪模式）期间时间显示才能持续刷新
        let timer = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self else { return }
            // 弹幕层未打开时 clock 为 nil，进度与时长仍需正常显示
            let clock = self.controller.clock
            let playing = clock?.isPlaying == true
            let t = max(clock?.currentTime ?? 0, 0)
            let m = Int(t) / 60, s = Int(t) % 60, d = Int(t * 10) % 10
            if self.controller.isCountingDown {
                self.playbackPanel.setPlayButton(symbol: "xmark", title: "取消 \(self.controller.countdownRemaining)")
                self.playbackPanel.setTimeDisplay(String(format: "⏳ %02d:%02d.%d", m, s, d))
            } else {
                self.playbackPanel.setPlayButton(symbol: playing ? "pause.fill" : "play.fill",
                                                 title: playing ? "暂停" : "播放")
                self.playbackPanel.setTimeDisplay(String(format: "%@ %02d:%02d.%d", playing ? "▶" : "⏸", m, s, d))
            }
            self.playbackPanel.updateProgress(currentTime: t, duration: self.totalDuration(), recentSeekAt: self.lastSeekAt)
            self.updatePlaybackStateLabels(currentTime: t)
            // 播放页状态行镜像来源页 statusLabel，两页共享一份提示文案
            if self.playbackPanel.statusLabel.stringValue != self.statusLabel.stringValue {
                self.playbackPanel.statusLabel.stringValue = self.statusLabel.stringValue
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        timeTimer = timer
    }

    private func updatePlaybackStateLabels(currentTime t: Double) {
        let playState: String
        if controller.isCountingDown {
            playState = "倒计时 \(controller.countdownRemaining)s"
        } else if controller.clock?.isPlaying == true {
            playState = "播放中"
        } else {
            playState = controller.rawDanmaku.isEmpty ? "待加载" : "已暂停"
        }

        let overlayState: String
        if controller.overlayWindow?.isVisible == true {
            overlayState = settings.mousePassthrough ? "穿透已开" : "可拖动"
        } else {
            overlayState = "弹幕层未打开"
        }

        let current = max(t, 0)
        let duration = totalDuration()
        let timeline: String
        if duration > 0 {
            timeline = "\(mmss(current)) / \(mmss(duration))"
        } else {
            timeline = mmss(current)
        }
        playbackPanel.updateState(play: playState, overlay: overlayState,
                                  timeline: timeline, count: "\(controller.rawDanmaku.count) 条")
    }

    /// 视频时长；本地 XML 导入无时长时退化为最后一条弹幕的时间
    private func totalDuration() -> Double {
        if let p = controller.currentPage, p.duration > 0 { return Double(p.duration) }
        if let last = controller.rawDanmaku.last?.time { return max(last.rounded(.up), 60) }
        return 0
    }

    private func parseOffset(_ text: String) -> Double? {
        var normalized = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if normalized.hasPrefix("+") { normalized.removeFirst() }
        for suffix in ["seconds", "second", "secs", "sec", "s", "秒"] where normalized.hasSuffix(suffix) {
            normalized.removeLast(suffix.count)
            break
        }
        normalized = normalized.trimmingCharacters(in: .whitespacesAndNewlines)
        return Double(normalized)
    }

    private func safeFilename(_ title: String, ext: String) -> String {
        let invalid = CharacterSet(charactersIn: "/\\?%*|\"<>:")
        let cleaned = title.components(separatedBy: invalid).joined(separator: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return (cleaned.isEmpty ? "danmaku" : cleaned) + "." + ext
    }

    private func mmss(_ t: Double) -> String {
        String(format: "%02d:%02d", Int(t) / 60, Int(t) % 60)
    }
}
