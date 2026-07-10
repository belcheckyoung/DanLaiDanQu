import AppKit
import QuartzCore

/// 弹幕渲染视图：CATextLayer + CADisplayLink 逐帧驱动，位置完全由 PlaybackClock 推导，
/// 因此暂停 / 快进 / 后退 / 倍速都天然生效（需求文档 7.3 / 7.4 节）
final class DanmakuRenderView: NSView {

    private struct ActiveItem {
        let layer: CATextLayer
        let danmaku: Danmaku
        let lane: Int
        let textWidth: CGFloat
        let speed: CGFloat       // 滚动弹幕像素/秒；固定弹幕为 0
        let expireTime: Double   // 时钟时间超过该值后移除
    }

    private struct LaneState {
        var lastEntryTime: Double = -1e9
        var lastWidth: CGFloat = 0
        var lastSpeed: CGFloat = 0
    }

    let clock = PlaybackClock()

    private var allDanmaku: [Danmaku] = []      // 过滤后、按时间排序
    private var nextIndex = 0
    private var active: [ActiveItem] = []
    private var scrollLanes: [LaneState] = []
    private var topLaneBusy: [Double] = []      // 车道占用到的时钟时间
    private var bottomLaneBusy: [Double] = []
    private var displayLink: CADisplayLink?
    private var lastFrameTime: Double = -1
    private var clearUntilWallClock: Date?      // 一键清屏 3 秒

    private let fixedDuration: Double = 5.0
    private let settings = SettingsStore.shared

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.masksToBounds = true
    }

    required init?(coder: NSCoder) { fatalError() }

    // MARK: - 数据

    func load(danmaku: [Danmaku]) {
        allDanmaku = danmaku.sorted { $0.time < $1.time }
        resync()
    }

    /// 时间轴跳变（seek/偏移调整）后重建屏上弹幕
    func resync() {
        removeAllActive()
        let t = clock.currentTime
        // 二分找到第一条 time >= t - scrollDuration 的弹幕，把仍在屏上的滚动弹幕补回来
        let windowStart = t - settings.scrollDuration
        var lo = 0, hi = allDanmaku.count
        while lo < hi {
            let mid = (lo + hi) / 2
            if allDanmaku[mid].time < windowStart { lo = mid + 1 } else { hi = mid }
        }
        nextIndex = lo
        // 推进到当前时间，途中弹幕以“正确的中途位置”入场
        spawnPending(until: t, allowMidFlight: true)
    }

    func startRendering() {
        guard displayLink == nil else { return }
        rebuildLanes()
        let link = displayLink(target: self, selector: #selector(frame(_:)))
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    func stopRendering() {
        displayLink?.invalidate()
        displayLink = nil
        removeAllActive()
    }

    // MARK: - 倒计时显示

    private var countdownLayer: CALayer?

    /// 在弹幕层正中央显示倒计时（HUD 风格深色圆角背板 + 大字）；传 nil 移除
    func showCountdown(_ seconds: Int?) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        countdownLayer?.removeFromSuperlayer()
        countdownLayer = nil
        if let seconds {
            let text = NSMutableAttributedString()
            text.append(NSAttributedString(string: "\(seconds)\n", attributes: [
                .font: NSFont.monospacedDigitSystemFont(ofSize: 96, weight: .heavy),
                .foregroundColor: NSColor.white,
            ]))
            text.append(NSAttributedString(string: "弹幕即将开始，请点击视频播放", attributes: [
                .font: NSFont.systemFont(ofSize: 21, weight: .medium),
                .foregroundColor: NSColor.white.withAlphaComponent(0.85),
            ]))

            let pillW: CGFloat = 420, pillH: CGFloat = 196
            let pill = CALayer()
            pill.backgroundColor = NSColor.black.withAlphaComponent(0.42).cgColor
            pill.cornerRadius = 28
            pill.masksToBounds = true
            pill.frame = CGRect(x: (bounds.width - pillW) / 2,
                                y: (bounds.height - pillH) / 2,
                                width: pillW, height: pillH)

            let textLayer = CATextLayer()
            textLayer.string = text
            textLayer.alignmentMode = .center
            textLayer.isWrapped = true
            textLayer.contentsScale = window?.backingScaleFactor ?? 2
            textLayer.frame = CGRect(x: 0, y: 8, width: pillW, height: pillH - 26)
            pill.addSublayer(textLayer)

            self.layer?.addSublayer(pill)
            countdownLayer = pill
        }
        CATransaction.commit()
    }

    /// 一键清屏 3 秒
    func clearScreen() {
        removeAllActive()
        clearUntilWallClock = Date().addingTimeInterval(3)
    }

    override func layout() {
        super.layout()
        rebuildLanes()
    }

    // MARK: - 帧驱动

    @objc private func frame(_ link: CADisplayLink) {
        let t = clock.currentTime

        if let until = clearUntilWallClock {
            if Date() < until { return }
            clearUntilWallClock = nil
        }

        // 时钟回退（用户按了后退）→ 整体重建
        if t < lastFrameTime - 0.001 {
            lastFrameTime = t
            resync()
            return
        }
        lastFrameTime = t

        if clock.isPlaying {
            spawnPending(until: t, allowMidFlight: false)
        }

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        var removed: [ActiveItem] = []
        active.removeAll { item in
            if t >= item.expireTime {
                removed.append(item)
                return true
            }
            if item.danmaku.mode == .scroll {
                let x = bounds.width - CGFloat(t - item.danmaku.time) * item.speed
                item.layer.frame.origin.x = x
            }
            return false
        }
        for item in removed { item.layer.removeFromSuperlayer() }
        CATransaction.commit()
    }

    private func spawnPending(until t: Double, allowMidFlight: Bool) {
        while nextIndex < allDanmaku.count && allDanmaku[nextIndex].time <= t {
            let d = allDanmaku[nextIndex]
            nextIndex += 1
            if allowMidFlight {
                if d.mode == .scroll || t - d.time < fixedDuration {
                    spawn(d, at: t)
                }
            } else if t - d.time < 0.5 {
                // 正常播放中只生成刚到时间的弹幕，避免累积爆发
                spawn(d, at: t)
            }
        }
    }

    // MARK: - 弹幕生成与轨道分配

    private func spawn(_ d: Danmaku, at now: Double) {
        let textLayer = makeLayer(for: d)
        let w = textLayer.frame.width
        let laneHeight = lineHeight()

        switch d.mode {
        case .scroll:
            let speed = (bounds.width + w) / CGFloat(settings.scrollDuration)
            guard let lane = allocateScrollLane(entryTime: d.time, width: w, speed: speed) else {
                return   // 所有车道都会碰撞且密度受限 → 丢弃
            }
            let x = bounds.width - CGFloat(now - d.time) * speed
            textLayer.frame.origin = CGPoint(x: x, y: yForLane(lane, height: laneHeight))
            layer?.addSublayer(textLayer)
            active.append(ActiveItem(layer: textLayer, danmaku: d, lane: lane,
                                     textWidth: w, speed: speed,
                                     expireTime: d.time + settings.scrollDuration))
        case .top:
            guard let lane = topLaneBusy.firstIndex(where: { $0 <= d.time }) else { return }
            topLaneBusy[lane] = d.time + fixedDuration
            textLayer.frame.origin = CGPoint(x: (bounds.width - w) / 2,
                                             y: yForLane(lane, height: laneHeight))
            layer?.addSublayer(textLayer)
            active.append(ActiveItem(layer: textLayer, danmaku: d, lane: lane,
                                     textWidth: w, speed: 0, expireTime: d.time + fixedDuration))
        case .bottom:
            guard let lane = bottomLaneBusy.firstIndex(where: { $0 <= d.time }) else { return }
            bottomLaneBusy[lane] = d.time + fixedDuration
            let y = laneHeight * CGFloat(lane + 1) + settings.laneSpacing
            textLayer.frame.origin = CGPoint(x: (bounds.width - w) / 2, y: y)
            layer?.addSublayer(textLayer)
            active.append(ActiveItem(layer: textLayer, danmaku: d, lane: lane,
                                     textWidth: w, speed: 0, expireTime: d.time + fixedDuration))
        case .other:
            break
        }
    }

    /// 滚动车道碰撞检测：
    /// 1) 前一条的尾部已离开右边缘；2) 本条更快时，追上前一条之前前一条已离屏
    private func allocateScrollLane(entryTime: Double, width: CGFloat, speed: CGFloat) -> Int? {
        var best: Int? = nil
        var bestSlack: Double = -.infinity
        for (i, lane) in scrollLanes.enumerated() {
            let dt = entryTime - lane.lastEntryTime
            let tailCleared = lane.lastSpeed * CGFloat(dt) >= lane.lastWidth
            let prevExit = lane.lastEntryTime + Double((bounds.width + lane.lastWidth) / max(lane.lastSpeed, 1))
            let noCatchUp = speed <= lane.lastSpeed
                || CGFloat(prevExit - entryTime) * speed <= bounds.width
            if tailCleared && noCatchUp {
                let slack = dt
                if slack > bestSlack {
                    bestSlack = slack
                    best = i
                }
            }
        }
        if let best {
            scrollLanes[best] = LaneState(lastEntryTime: entryTime, lastWidth: width, lastSpeed: speed)
            return best
        }
        // 无空闲车道：选最久未用车道容忍重叠，保证热门片段不至于大量丢弃
        if let fallback = scrollLanes.indices.min(by: { scrollLanes[$0].lastEntryTime < scrollLanes[$1].lastEntryTime }) {
            scrollLanes[fallback] = LaneState(lastEntryTime: entryTime, lastWidth: width, lastSpeed: speed)
            return fallback
        }
        return nil
    }

    // MARK: - 布局工具

    private func lineHeight() -> CGFloat {
        settings.fontSize * 1.35 + settings.laneSpacing
    }

    private func rebuildLanes() {
        let usable = bounds.height * CGFloat(settings.displayAreaRatio)
        let count = max(Int(usable / lineHeight()), 1)
        if scrollLanes.count != count {
            scrollLanes = Array(repeating: LaneState(), count: count)
        }
        let fixedCount = max(count / 2, 1)
        if topLaneBusy.count != fixedCount {
            topLaneBusy = Array(repeating: -1e9, count: fixedCount)
            bottomLaneBusy = Array(repeating: -1e9, count: fixedCount)
        }
    }

    /// AppKit 坐标系 y 向上；弹幕从视图顶部往下排轨道
    private func yForLane(_ lane: Int, height: CGFloat) -> CGFloat {
        bounds.height - height * CGFloat(lane + 1)
    }

    private func removeAllActive() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for item in active { item.layer.removeFromSuperlayer() }
        CATransaction.commit()
        active.removeAll()
        for i in scrollLanes.indices { scrollLanes[i] = LaneState() }
        for i in topLaneBusy.indices { topLaneBusy[i] = -1e9 }
        for i in bottomLaneBusy.indices { bottomLaneBusy[i] = -1e9 }
        lastFrameTime = clock.currentTime
    }

    // MARK: - 图层构建

    private func makeLayer(for d: Danmaku) -> CATextLayer {
        let font = Self.boldFont(family: settings.fontName, size: settings.fontSize)
        let color = NSColor(red: CGFloat((d.color >> 16) & 0xFF) / 255,
                            green: CGFloat((d.color >> 8) & 0xFF) / 255,
                            blue: CGFloat(d.color & 0xFF) / 255,
                            alpha: 1)
        // 双重描边效果：strokeWidth 为负时同时填充+描边
        let attr = NSAttributedString(string: d.text, attributes: [
            .font: font,
            .foregroundColor: color,
            .strokeColor: NSColor.black,
            .strokeWidth: -3.0,
        ])
        let size = attr.size()
        let textLayer = CATextLayer()
        textLayer.string = attr
        textLayer.frame = CGRect(x: 0, y: 0, width: ceil(size.width) + 4, height: ceil(size.height) + 2)
        textLayer.contentsScale = window?.backingScaleFactor ?? 2
        textLayer.opacity = Float(settings.opacity)
        return textLayer
    }

    /// 取字体族的最粗可用字重（苹方为 Semibold），找不到则用系统粗体
    static func boldFont(family: String, size: CGFloat) -> NSFont {
        if let f = NSFontManager.shared.font(withFamily: family, traits: .boldFontMask,
                                             weight: 9, size: size) {
            return f
        }
        return .boldSystemFont(ofSize: size)
    }
}
