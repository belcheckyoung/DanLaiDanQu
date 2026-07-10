import AppKit

enum OverlayTheme {
    /// B 站粉，用于主操作强调色
    static let accentPink = NSColor(srgbRed: 0.984, green: 0.447, blue: 0.600, alpha: 1)
    static let glassTint = NSColor.controlBackgroundColor.withAlphaComponent(0.22)
    static let glassStroke = NSColor.white.withAlphaComponent(0.22)
    static let cardRadius: CGFloat = 14
    static let compactRadius: CGFloat = 9
    static let controlHeight: CGFloat = 30
    static let windowContentInset: CGFloat = 28
    static let sheetContentInset: CGFloat = 24

    static func configureGlassWindow(_ window: NSWindow) {
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.styleMask.insert(.fullSizeContentView)
        window.styleMask.insert(.resizable)
        window.isMovableByWindowBackground = true
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
    }

    /// Sheet 版玻璃配置：不可缩放、不可背景拖动（sheet 不应独立移动），防御性关闭 releasedWhenClosed
    static func configureGlassSheet(_ window: NSWindow) {
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.styleMask.insert(.fullSizeContentView)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.isReleasedWhenClosed = false
    }
}

enum MainWindowUI {
    static func hstack(_ views: NSView...) -> NSStackView {
        let stack = NSStackView(views: views)
        stack.orientation = .horizontal
        stack.spacing = 6
        return stack
    }

    static func equalRow(_ views: [NSView]) -> NSStackView {
        let stack = NSStackView(views: views)
        stack.orientation = .horizontal
        stack.spacing = 6
        stack.distribution = .fillEqually
        return stack
    }

    static func smallButton(_ title: String, target: AnyObject?, action: Selector) -> NSButton {
        let button = NSButton(title: title, target: target, action: action)
        button.controlSize = .small
        button.font = .systemFont(ofSize: 11)
        button.bezelStyle = .glass
        button.imagePosition = .imageLeading
        return button
    }

    static func toolButton(_ symbol: String, _ title: String, target: AnyObject?, action: Selector) -> NSButton {
        let button = NSButton(title: title, target: target, action: action)
        button.controlSize = .small
        button.font = .systemFont(ofSize: 12, weight: .medium)
        button.bezelStyle = .glass
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)
        button.imagePosition = .imageLeading
        return button
    }

    static func label(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 12)
        return label
    }

    static func windowBackdrop() -> NSVisualEffectView {
        let backdrop = NSVisualEffectView()
        backdrop.material = .underWindowBackground
        backdrop.blendingMode = .behindWindow
        backdrop.state = .active
        return backdrop
    }

    static func settingTitle(_ title: String, _ valueLabel: NSTextField) -> NSView {
        let titleLabel = label(title)
        titleLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)
        valueLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        valueLabel.textColor = .secondaryLabelColor
        valueLabel.alignment = .right
        valueLabel.setContentHuggingPriority(.required, for: .horizontal)
        let row = hstack(titleLabel, valueLabel)
        row.spacing = 4
        return row
    }

    static func statusPill(_ symbol: String, _ textField: NSTextField) -> NSView {
        let box = NSGlassEffectView()
        box.cornerRadius = OverlayTheme.compactRadius
        box.translatesAutoresizingMaskIntoConstraints = false
        box.heightAnchor.constraint(equalToConstant: 28).isActive = true

        let icon = NSImageView(image: NSImage(systemSymbolName: symbol, accessibilityDescription: nil) ?? NSImage())
        icon.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 11, weight: .semibold)
        icon.contentTintColor = OverlayTheme.accentPink
        icon.setContentHuggingPriority(.required, for: .horizontal)

        textField.font = .systemFont(ofSize: 11, weight: .medium)
        textField.textColor = .labelColor
        textField.lineBreakMode = .byTruncatingTail
        textField.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let row = hstack(icon, textField)
        row.alignment = .centerY
        box.contentView = padded(row, top: 5, side: 8)
        return box
    }

    /// 分区内容纵向堆叠，所有行拉满卡片宽度
    static func sectionStack(_ views: [NSView]) -> NSStackView {
        let stack = NSStackView(views: views)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        for view in views {
            view.translatesAutoresizingMaskIntoConstraints = false
            view.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }
        return stack
    }

    /// 内边距容器：NSGlassEffectView 会用私有 ContentHolderView 接管 contentView 的边缘定位，
    /// 直接对 glass 做内边距约束会被静默覆盖（左/顶边距丢失），留白必须做进内容自身。
    private static func padded(_ content: NSView, top: CGFloat, side: CGFloat) -> NSView {
        let wrapper = NSView()
        wrapper.translatesAutoresizingMaskIntoConstraints = false
        content.translatesAutoresizingMaskIntoConstraints = false
        wrapper.addSubview(content)
        NSLayoutConstraint.activate([
            content.topAnchor.constraint(equalTo: wrapper.topAnchor, constant: top),
            content.leadingAnchor.constraint(equalTo: wrapper.leadingAnchor, constant: side),
            content.trailingAnchor.constraint(equalTo: wrapper.trailingAnchor, constant: -side),
            content.bottomAnchor.constraint(equalTo: wrapper.bottomAnchor, constant: -top),
        ])
        return wrapper
    }

    /// 圆角液态玻璃卡片
    static func card(_ content: NSView) -> NSView {
        let glass = NSGlassEffectView()
        glass.cornerRadius = OverlayTheme.cardRadius
        glass.translatesAutoresizingMaskIntoConstraints = false
        glass.contentView = padded(content, top: 16, side: 20)
        return glass
    }

    static func headerBar(_ content: NSView) -> NSView {
        let glass = NSGlassEffectView()
        glass.cornerRadius = 18
        glass.translatesAutoresizingMaskIntoConstraints = false
        glass.contentView = padded(content, top: 12, side: 16)
        return glass
    }

    /// SF Symbol 图标 + 文字的分区标题
    static func sectionHeader(_ symbol: String, _ text: String) -> NSView {
        let icon = NSImageView(image: NSImage(systemSymbolName: symbol, accessibilityDescription: text) ?? NSImage())
        icon.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 11, weight: .semibold)
        icon.contentTintColor = .secondaryLabelColor
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 11.5, weight: .semibold)
        label.textColor = .secondaryLabelColor
        let row = hstack(icon, label)
        row.spacing = 5
        return row
    }
}

/// NSScrollView 文档视图需要翻转坐标，内容才能从顶部开始排布
final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}
