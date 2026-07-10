import AppKit

/// 透明置顶弹幕层（需求文档 5.1.3 / 7.5 节）
/// - 透明背景、始终置顶、可拖拽移动、可调整大小
/// - 可切换鼠标穿透；穿透关闭时可整窗拖动
final class OverlayWindow: NSPanel {

    let renderView = DanmakuRenderView()

    /// 穿透开启时窗口完全不响应鼠标，点击直接落到下层播放器
    var mousePassthrough: Bool = true {
        didSet {
            ignoresMouseEvents = mousePassthrough
            updateBorder()
        }
    }

    init() {
        // 默认覆盖主屏上方 45% 区域
        let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let height = screen.height * 0.45
        let frame = NSRect(x: screen.minX, y: screen.maxY - height,
                           width: screen.width, height: height)

        super.init(contentRect: frame,
                   styleMask: [.borderless, .nonactivatingPanel, .resizable],
                   backing: .buffered, defer: false)

        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .screenSaver                       // 高于普通窗口与浮动窗口
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        isMovableByWindowBackground = true         // 非穿透模式下可整窗拖动
        hidesOnDeactivate = false
        isFloatingPanel = true
        becomesKeyOnlyIfNeeded = true

        contentView = renderView
        ignoresMouseEvents = mousePassthrough

        restoreFrame()

        // 显示器插拔后重新校验位置，避免弹幕层留在已断开的屏幕上
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main) { [weak self] _ in
            self?.ensureOnVisibleScreen()
        }
    }

    /// 弹幕层若整体落在所有屏幕之外（如保存位置的显示器已断开），拉回主屏默认位置
    func ensureOnVisibleScreen() {
        let screens = NSScreen.screens
        guard !screens.isEmpty else { return }
        let onSomeScreen = screens.contains { $0.frame.intersects(frame.insetBy(dx: 40, dy: 40)) }
        if !onSomeScreen {
            let screen = NSScreen.main?.visibleFrame ?? screens[0].visibleFrame
            let height = screen.height * 0.45
            setFrame(NSRect(x: screen.minX, y: screen.maxY - height,
                            width: screen.width, height: height), display: true)
        }
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    /// 非穿透（调整位置）模式下显示细边框提示当前范围
    private func updateBorder() {
        guard let layer = renderView.layer else { return }
        if mousePassthrough {
            layer.borderWidth = 0
        } else {
            layer.borderWidth = 2
            layer.borderColor = NSColor.systemPink.withAlphaComponent(0.8).cgColor
        }
    }

    // MARK: - 位置记忆

    func saveFrame() {
        Database.shared.setSetting("overlayFrame", NSStringFromRect(frame))
    }

    private func restoreFrame() {
        if let s = Database.shared.getSetting("overlayFrame") {
            let f = NSRectFromString(s)
            if f.width > 100 && f.height > 50 { setFrame(f, display: false) }
        }
        ensureOnVisibleScreen()
    }
}
