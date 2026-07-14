import Foundation

/// 独立播放时钟：不依赖任何播放器，由用户手动校准（需求文档 7.4 节）
final class PlaybackClock {

    private(set) var isPlaying = false
    private var storedRate: Double = 1.0
    var rate: Double {
        get { storedRate }
        set {
            // 先按旧倍速结算已流逝的时间，再切换倍速，避免时间轴跳变。
            let settledTime = currentTime
            storedRate = min(max(newValue, 0.1), 4.0)
            baseTime = settledTime
            baseDate = now()
            onStateChange?()
        }
    }

    /// 时钟基准：currentTime = baseTime + (now - baseDate) * rate
    private var baseTime: Double = 0
    private var baseDate: Date
    private let now: () -> Date

    var onStateChange: (() -> Void)?

    var currentTime: Double {
        guard isPlaying else { return baseTime }
        return baseTime + now().timeIntervalSince(baseDate) * rate
    }

    init(now: @escaping () -> Date = Date.init) {
        self.now = now
        self.baseDate = now()
    }

    func play() {
        guard !isPlaying else { return }
        baseDate = now()
        isPlaying = true
        onStateChange?()
    }

    func pause() {
        guard isPlaying else { return }
        baseTime = currentTime
        isPlaying = false
        onStateChange?()
    }

    func toggle() {
        isPlaying ? pause() : play()
    }

    /// 跳转到绝对时间
    func seek(to time: Double) {
        baseTime = max(time, 0)
        baseDate = now()
        onStateChange?()
    }

    /// 相对偏移（正数快进，负数后退）
    func adjust(by delta: Double) {
        seek(to: currentTime + delta)
    }

    /// 将当前时刻设为 0 秒并开始播放（「从此刻同步」）
    func syncFromNow() {
        baseTime = 0
        baseDate = now()
        isPlaying = true
        onStateChange?()
    }
}
