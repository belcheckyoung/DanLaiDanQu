import AppKit

final class PlaybackControlPanel: NSStackView {
    struct Actions {
        let toggleOverlay: Selector
        let syncNow: Selector
        let togglePlay: Selector
        let delayToggled: Selector
        let progressDragged: Selector
        let back5: Selector
        let back1: Selector
        let applyOffset: Selector
        let forward1: Selector
        let forward5: Selector
        let saveProfile: Selector
        let clearScreen: Selector
        let openSettings: Selector
    }

    let overlayButton = NSButton(title: "打开弹幕层", target: nil, action: nil)
    let syncButton = NSButton(title: "从 0 秒同步", target: nil, action: nil)
    let playButton = NSButton(title: "播放", target: nil, action: nil)
    let delaySwitch = NSSwitch()
    let timeLabel = NSTextField(labelWithString: "00:00.0")
    let durationLabel = NSTextField(labelWithString: "00:00 / 00:00")
    let offsetField = NSTextField()
    let statusLabel = NSTextField(labelWithString: "")

    private let progressSlider = NSSlider(value: 0, minValue: 0, maxValue: 1, target: nil, action: nil)
    private let playStateLabel = NSTextField(labelWithString: "待机")
    private let overlayStateLabel = NSTextField(labelWithString: "弹幕层未打开")
    private let timelineStateLabel = NSTextField(labelWithString: "00:00")
    private let countStateLabel = NSTextField(labelWithString: "0 条")

    init(target: AnyObject, actions: Actions) {
        super.init(frame: .zero)
        configure(target: target, actions: actions)
    }

    required init?(coder: NSCoder) { fatalError() }

    var delayedStart: Bool {
        get { delaySwitch.state == .on }
        set { delaySwitch.state = newValue ? .on : .off }
    }

    var offsetText: String {
        get { offsetField.stringValue }
        set { offsetField.stringValue = newValue }
    }

    var progressValue: Double { progressSlider.doubleValue }

    private func configure(target: AnyObject, actions: Actions) {
        orientation = .vertical
        alignment = .leading
        spacing = 8

        statusLabel.font = .systemFont(ofSize: 12)
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.lineBreakMode = .byTruncatingTail

        offsetField.placeholderString = "+12.5s"
        offsetField.font = .systemFont(ofSize: 12)
        offsetField.widthAnchor.constraint(equalToConstant: 88).isActive = true

        durationLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        durationLabel.textColor = .secondaryLabelColor
        durationLabel.setContentHuggingPriority(.required, for: .horizontal)
        progressSlider.setContentHuggingPriority(.defaultLow, for: .horizontal)
        progressSlider.isEnabled = false
        progressSlider.isContinuous = true
        progressSlider.target = target
        progressSlider.action = actions.progressDragged

        playButton.bezelStyle = .glass
        playButton.bezelColor = OverlayTheme.accentPink
        playButton.contentTintColor = .white
        playButton.font = .systemFont(ofSize: 13, weight: .semibold)
        playButton.image = NSImage(systemSymbolName: "play.fill", accessibilityDescription: "播放")
        playButton.imagePosition = .imageLeading
        playButton.widthAnchor.constraint(equalToConstant: 92).isActive = true
        playButton.target = target
        playButton.action = actions.togglePlay

        timeLabel.font = .monospacedDigitSystemFont(ofSize: 14, weight: .medium)
        timeLabel.setContentHuggingPriority(.required, for: .horizontal)

        overlayButton.bezelStyle = .glass
        overlayButton.image = NSImage(systemSymbolName: "rectangle.on.rectangle", accessibilityDescription: "弹幕层")
        overlayButton.imagePosition = .imageLeading
        overlayButton.target = target
        overlayButton.action = actions.toggleOverlay

        syncButton.bezelStyle = .glass
        syncButton.image = NSImage(systemSymbolName: "timer", accessibilityDescription: "从 0 秒同步")
        syncButton.imagePosition = .imageLeading
        syncButton.target = target
        syncButton.action = actions.syncNow

        delaySwitch.controlSize = .mini
        delaySwitch.target = target
        delaySwitch.action = actions.delayToggled

        let stateRow = MainWindowUI.equalRow([
            MainWindowUI.statusPill("play.circle.fill", playStateLabel),
            MainWindowUI.statusPill("rectangle.on.rectangle", overlayStateLabel),
            MainWindowUI.statusPill("clock", timelineStateLabel),
            MainWindowUI.statusPill("text.bubble", countStateLabel),
        ])

        let progressRow = MainWindowUI.hstack(playButton, timeLabel, progressSlider, durationLabel)
        progressRow.alignment = .centerY

        let delayLabel = MainWindowUI.label("5秒后开始")
        delayLabel.setContentHuggingPriority(.required, for: .horizontal)
        let delayRow = MainWindowUI.hstack(delaySwitch, delayLabel)
        delayRow.alignment = .centerY

        let actionRow = MainWindowUI.hstack(
            overlayButton,
            syncButton,
            MainWindowUI.toolButton("square.and.arrow.down", "保存", target: target, action: actions.saveProfile),
            MainWindowUI.toolButton("xmark.circle", "清屏", target: target, action: actions.clearScreen),
            MainWindowUI.toolButton("slider.horizontal.3", "设置", target: target, action: actions.openSettings)
        )
        actionRow.alignment = .centerY

        let adjustRow = MainWindowUI.hstack(
            MainWindowUI.smallButton("-5s", target: target, action: actions.back5),
            MainWindowUI.smallButton("-1s", target: target, action: actions.back1),
            offsetField,
            MainWindowUI.smallButton("应用", target: target, action: actions.applyOffset),
            MainWindowUI.smallButton("+1s", target: target, action: actions.forward1),
            MainWindowUI.smallButton("+5s", target: target, action: actions.forward5)
        )
        adjustRow.alignment = .centerY

        for view in [
            MainWindowUI.sectionHeader("play.circle.fill", "第二步 · 同步播放"),
            stateRow, progressRow, delayRow, actionRow, adjustRow, statusLabel,
        ] {
            addArrangedSubview(view)
            view.translatesAutoresizingMaskIntoConstraints = false
            view.widthAnchor.constraint(equalTo: widthAnchor).isActive = true
        }
    }

    func setOverlayVisible(_ visible: Bool) {
        overlayButton.title = visible ? "关闭弹幕层" : "打开弹幕层"
        overlayButton.image = NSImage(systemSymbolName: visible ? "rectangle.badge.xmark" : "rectangle.on.rectangle",
                                      accessibilityDescription: overlayButton.title)
    }

    func setPlayButton(symbol: String, title: String) {
        guard playButton.title != title else { return }
        playButton.title = title
        playButton.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)
    }

    func setTimeDisplay(_ text: String) {
        timeLabel.stringValue = text
    }

    func setDraggedTime(_ time: Double, playing: Bool, duration: Double) {
        let state = playing ? "▶" : "⏸"
        timeLabel.stringValue = String(format: "%@ %02d:%02d.%d",
                                       state, Int(time) / 60, Int(time) % 60, Int(time * 10) % 10)
        durationLabel.stringValue = "\(Self.mmss(time)) / \(Self.mmss(duration))"
    }

    func updateProgress(currentTime: Double, duration: Double, recentSeekAt: Date) {
        progressSlider.isEnabled = duration > 0
        durationLabel.stringValue = "\(Self.mmss(currentTime)) / \(Self.mmss(duration))"
        let dragging = (progressSlider.cell?.isHighlighted ?? false)
            || Date().timeIntervalSince(recentSeekAt) < 0.4
        if !dragging && duration > 0 {
            progressSlider.maxValue = duration
            progressSlider.doubleValue = min(currentTime, duration)
        }
    }

    func updateState(play: String, overlay: String, timeline: String, count: String) {
        playStateLabel.stringValue = play
        overlayStateLabel.stringValue = overlay
        timelineStateLabel.stringValue = timeline
        countStateLabel.stringValue = count
    }

    private static func mmss(_ time: Double) -> String {
        String(format: "%02d:%02d", Int(time) / 60, Int(time) % 60)
    }
}
