import AppKit

/// 主窗口内的全屏设置页；与主内容共用同一个窗口，避免 Sheet 四周露出父页面边框。
final class DisplaySettingsPage: NSVisualEffectView {
    struct Actions {
        let close: Selector
        let fontChanged: Selector
        let opacityChanged: Selector
        let speedChanged: Selector
        let areaChanged: Selector
        let densityChanged: Selector
        let keywordsChanged: Selector
        let checksChanged: Selector
    }

    private let fontSlider = NSSlider(value: 28, minValue: 14, maxValue: 60, target: nil, action: nil)
    private let opacitySlider = NSSlider(value: 0.9, minValue: 0.1, maxValue: 1.0, target: nil, action: nil)
    private let speedSlider = NSSlider(value: 12, minValue: 4, maxValue: 24, target: nil, action: nil)
    private let areaSlider = NSSlider(value: 1.0, minValue: 0.2, maxValue: 1.0, target: nil, action: nil)
    private let densityPopup = NSPopUpButton()

    private let fontValueLabel = NSTextField(labelWithString: "")
    private let opacityValueLabel = NSTextField(labelWithString: "")
    private let speedValueLabel = NSTextField(labelWithString: "")
    private let areaValueLabel = NSTextField(labelWithString: "")

    private let keywordField = NSTextField()
    private let topCheck = NSButton(checkboxWithTitle: "顶部弹幕", target: nil, action: nil)
    private let bottomCheck = NSButton(checkboxWithTitle: "底部弹幕", target: nil, action: nil)
    private let colorCheck = NSButton(checkboxWithTitle: "彩色弹幕", target: nil, action: nil)
    private let mergeCheck = NSButton(checkboxWithTitle: "合并重复", target: nil, action: nil)

    private let densityValues = [0, 30, 20, 10, 5]

    init(target: AnyObject, actions: Actions) {
        super.init(frame: .zero)
        material = .underWindowBackground
        blendingMode = .behindWindow
        state = .active
        configure(target: target, actions: actions)
    }

    required init?(coder: NSCoder) { fatalError() }

    var fontSize: Double { fontSlider.doubleValue }
    var opacity: Double { opacitySlider.doubleValue }
    var scrollDuration: Double { speedSlider.doubleValue }
    var displayAreaRatio: Double { areaSlider.doubleValue }
    var maxPerSecond: Int { densityValues[densityPopup.indexOfSelectedItem] }

    func restore(from settings: SettingsStore) {
        fontSlider.doubleValue = settings.fontSize
        opacitySlider.doubleValue = settings.opacity
        speedSlider.doubleValue = settings.scrollDuration
        areaSlider.doubleValue = settings.displayAreaRatio
        syncDensityPopup(maxPerSecond: settings.maxPerSecond)
        topCheck.state = settings.rules.showTop ? .on : .off
        bottomCheck.state = settings.rules.showBottom ? .on : .off
        colorCheck.state = settings.rules.blockColored ? .off : .on
        mergeCheck.state = settings.rules.mergeDuplicates ? .on : .off
        keywordField.stringValue = displayText(for: settings.rules)
        updateValueLabels(from: settings)
    }

    func updateValueLabels(from settings: SettingsStore) {
        fontValueLabel.stringValue = "\(Int(settings.fontSize)) pt"
        opacityValueLabel.stringValue = "\(Int(settings.opacity * 100))%"
        speedValueLabel.stringValue = String(format: "%.0f 秒", settings.scrollDuration)
        areaValueLabel.stringValue = "\(Int(settings.displayAreaRatio * 100))%"
    }

    func rules(basedOn existing: FilterRules) -> FilterRules {
        var rules = existing
        var keywords: [String] = []
        var regexes: [String] = []
        for text in Self.tokenize(keywordField.stringValue) {
            if text.hasPrefix("/") && text.hasSuffix("/") && text.count > 2 {
                regexes.append(String(text.dropFirst().dropLast()))
            } else {
                keywords.append(text)
            }
        }
        rules.keywords = keywords
        rules.regexPatterns = regexes
        rules.showTop = topCheck.state == .on
        rules.showBottom = bottomCheck.state == .on
        rules.blockColored = colorCheck.state == .off
        rules.mergeDuplicates = mergeCheck.state == .on
        return rules
    }

    /// 按逗号分词，但 /正则/ 段内的逗号不作分隔符（如 /哈{3,}/），支持 \/ 转义
    static func tokenize(_ input: String) -> [String] {
        var tokens: [String] = []
        var current = ""
        var inRegex = false
        var previous: Character?
        for ch in input {
            if (ch == "," || ch == "，") && !inRegex {
                tokens.append(current)
                current = ""
                previous = nil
                continue
            }
            if ch == "/" {
                if !inRegex && current.trimmingCharacters(in: .whitespaces).isEmpty {
                    inRegex = true                     // 斜杠起头 → 进入正则段
                } else if inRegex && previous != "\\" {
                    inRegex = false                    // 未转义的斜杠 → 正则段结束
                }
            }
            current.append(ch)
            previous = ch
        }
        tokens.append(current)
        return tokens.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
    }

    private func configure(target: AnyObject, actions: Actions) {
        densityPopup.addItems(withTitles: ["密度不限", "每秒 30 条", "每秒 20 条", "每秒 10 条", "每秒 5 条"])
        keywordField.placeholderString = "屏蔽关键词，逗号分隔；/正则/ 用斜杠包裹"

        let sliders: [(NSSlider, Selector)] = [
            (fontSlider, actions.fontChanged),
            (opacitySlider, actions.opacityChanged),
            (speedSlider, actions.speedChanged),
            (areaSlider, actions.areaChanged),
        ]
        for (slider, selector) in sliders {
            slider.target = target
            slider.action = selector
            slider.isContinuous = false
            slider.widthAnchor.constraint(equalToConstant: 340).isActive = true
        }

        densityPopup.target = target
        densityPopup.action = actions.densityChanged
        keywordField.target = target
        keywordField.action = actions.keywordsChanged
        for check in [topCheck, bottomCheck, colorCheck, mergeCheck] {
            check.target = target
            check.action = actions.checksChanged
        }

        let settingsGrid = NSGridView(views: [
            [MainWindowUI.settingTitle("字号", fontValueLabel), fontSlider],
            [MainWindowUI.settingTitle("透明度", opacityValueLabel), opacitySlider],
            [MainWindowUI.settingTitle("滚动时长", speedValueLabel), speedSlider],
            [MainWindowUI.settingTitle("显示区域", areaValueLabel), areaSlider],
            [MainWindowUI.label("弹幕密度"), densityPopup],
        ])
        settingsGrid.rowSpacing = 6
        settingsGrid.column(at: 0).width = 92

        let checkRow = MainWindowUI.hstack(topCheck, bottomCheck, colorCheck, mergeCheck)

        let backButton = NSButton(title: "返回", target: target, action: actions.close)
        backButton.bezelStyle = .glass
        backButton.image = NSImage(systemSymbolName: "chevron.left", accessibilityDescription: "返回")
        backButton.imagePosition = .imageLeading
        backButton.keyEquivalent = "\u{1b}"

        let pageTitle = NSTextField(labelWithString: "显示与屏蔽设置")
        pageTitle.font = .systemFont(ofSize: 20, weight: .bold)
        pageTitle.setContentHuggingPriority(.required, for: .horizontal)

        let header = NSStackView()
        header.orientation = .horizontal
        header.alignment = .centerY
        header.spacing = 12
        header.addView(backButton, in: .leading)
        header.addView(pageTitle, in: .leading)

        let saveButton = NSButton(title: "保存设置", target: target, action: actions.close)
        saveButton.bezelStyle = .glass
        saveButton.bezelColor = OverlayTheme.accentPink.withAlphaComponent(0.42)
        saveButton.image = NSImage(systemSymbolName: "checkmark", accessibilityDescription: "保存设置")
        saveButton.imagePosition = .imageLeading
        saveButton.keyEquivalent = "\r"
        let footer = NSStackView()
        footer.orientation = .horizontal
        footer.addView(saveButton, in: .trailing)

        let stack = NSStackView(views: [
            MainWindowUI.card(MainWindowUI.sectionStack([MainWindowUI.sectionHeader("slider.horizontal.3", "显示设置"), settingsGrid])),
            MainWindowUI.card(MainWindowUI.sectionStack([MainWindowUI.sectionHeader("eye.slash.fill", "屏蔽"), keywordField, checkRow])),
        ])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        for view in stack.arrangedSubviews {
            view.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }

        let document = FlippedView()
        document.translatesAutoresizingMaskIntoConstraints = false
        document.addSubview(stack)

        let scroll = NSScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.automaticallyAdjustsContentInsets = false
        scroll.documentView = document

        header.translatesAutoresizingMaskIntoConstraints = false
        footer.translatesAutoresizingMaskIntoConstraints = false
        addSubview(header)
        addSubview(scroll)
        addSubview(footer)

        let inset = OverlayTheme.windowContentInset
        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: topAnchor, constant: 48),
            header.leadingAnchor.constraint(equalTo: leadingAnchor, constant: inset),
            header.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -inset),

            footer.leadingAnchor.constraint(equalTo: leadingAnchor, constant: inset),
            footer.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -inset),
            footer.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -24),

            scroll.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 16),
            scroll.leadingAnchor.constraint(equalTo: leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: footer.topAnchor, constant: -12),

            document.topAnchor.constraint(equalTo: scroll.contentView.topAnchor),
            document.leadingAnchor.constraint(equalTo: scroll.contentView.leadingAnchor),
            document.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor),

            stack.topAnchor.constraint(equalTo: document.topAnchor),
            stack.leadingAnchor.constraint(equalTo: document.leadingAnchor, constant: inset),
            stack.trailingAnchor.constraint(equalTo: document.trailingAnchor, constant: -inset),
            stack.bottomAnchor.constraint(equalTo: document.bottomAnchor),
        ])
    }

    private func syncDensityPopup(maxPerSecond: Int) {
        let index = densityValues.firstIndex(of: maxPerSecond) ?? 0
        densityPopup.selectItem(at: index)
    }

    private func displayText(for rules: FilterRules) -> String {
        let regexes = rules.regexPatterns.map { "/\($0)/" }
        return (rules.keywords + regexes).joined(separator: ", ")
    }
}
