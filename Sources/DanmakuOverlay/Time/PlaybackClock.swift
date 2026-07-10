import Foundation

/// 独立播放时钟：不依赖任何播放器，由用户手动校准（需求文档 7.4 节）
final class PlaybackClock {

    private(set) var isPlaying = false
    var rate: Double = 1.0 {
        didSet { rebase() }
    }

    /// 时钟基准：currentTime = baseTime + (now - baseDate) * rate
    private var baseTime: Double = 0
    private var baseDate = Date()

    var onStateChange: (() -> Void)?

    var currentTime: Double {
        guard isPlaying else { return baseTime }
        return baseTime + Date().timeIntervalSince(baseDate) * rate
    }

    func play() {
        guard !isPlaying else { return }
        baseDate = Date()
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
        baseDate = Date()
        onStateChange?()
    }

    /// 相对偏移（正数快进，负数后退）
    func adjust(by delta: Double) {
        seek(to: currentTime + delta)
    }

    /// 将当前时刻设为 0 秒并开始播放（「从此刻同步」）
    func syncFromNow() {
        baseTime = 0
        baseDate = Date()
        isPlaying = true
        onStateChange?()
    }

    private func rebase() {
        baseTime = currentTime
        baseDate = Date()
        onStateChange?()
    }
}
