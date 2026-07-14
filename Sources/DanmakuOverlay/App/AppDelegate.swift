import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {

    private var mainWindowController: MainWindowController?
    private var statusItem: NSStatusItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        buildMenu()
        buildStatusItem()

        showMainWindow()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false   // 弹幕层可能仍在工作，主窗口关闭不退出
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showMainWindow()
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        AppController.shared.saveSyncProfile()
        AppController.shared.overlayWindow?.saveFrame()
    }

    // MARK: - 菜单栏图标（需求文档 7.5：菜单栏快速控制）

    private func buildStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.title = "弹"
        let menu = NSMenu()
        menu.addItem(withTitle: "显示主窗口", action: #selector(showMain), keyEquivalent: "").target = self
        menu.addItem(withTitle: "打开/关闭弹幕层 ⌘⇧H", action: #selector(toggleOverlay), keyEquivalent: "").target = self
        menu.addItem(withTitle: "播放/暂停弹幕 ⌘⇧空格", action: #selector(togglePlay), keyEquivalent: "").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "退出", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        item.menu = menu
        statusItem = item
    }

    @objc private func showMain() {
        showMainWindow()
    }

    @objc private func openSettings() {
        showMain()
        mainWindowController?.openSettingsSheet()
    }

    @objc private func toggleOverlay() { AppController.shared.toggleOverlay() }
    @objc private func togglePlay() {
        let controller = AppController.shared
        if controller.clock.isPlaying {
            controller.pausePlayback()
        } else {
            if controller.overlayWindow?.isVisible != true { controller.openOverlay() }
            controller.clock.play()
        }
    }

    // MARK: - 主菜单（保证 ⌘C/⌘V/⌘Q 可用）

    private func buildMenu() {
        let mainMenu = NSMenu()

        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "关于 弹来弹去", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        let settingsItem = NSMenuItem(title: "显示与屏蔽设置…", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        appMenu.addItem(settingsItem)
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "退出", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)

        let editMenuItem = NSMenuItem()
        let editMenu = NSMenu(title: "编辑")
        editMenu.addItem(withTitle: "撤销", action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(withTitle: "重做", action: Selector(("redo:")), keyEquivalent: "Z")
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "剪切", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "拷贝", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "粘贴", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "全选", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editMenuItem.submenu = editMenu
        mainMenu.addItem(editMenuItem)

        // 「控制」菜单：nil target 走响应链到 MainWindowController，两个页面都可用
        let controlMenuItem = NSMenuItem()
        let controlMenu = NSMenu(title: "控制")
        controlMenu.addItem(withTitle: "播放 / 暂停弹幕", action: #selector(MainWindowController.togglePlay), keyEquivalent: "p")
        controlMenu.addItem(withTitle: "从 0 秒同步", action: #selector(MainWindowController.syncNow), keyEquivalent: "s")
        controlMenuItem.submenu = controlMenu
        mainMenu.addItem(controlMenuItem)

        NSApp.mainMenu = mainMenu
    }

    private func showMainWindow() {
        let controller: MainWindowController
        if let existing = mainWindowController {
            controller = existing
        } else {
            controller = MainWindowController()
            mainWindowController = controller
        }
        controller.showWindow(nil)
        controller.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
