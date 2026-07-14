import Foundation

enum TimelineFormatter {
    static func string(from seconds: Double) -> String {
        let safe = seconds.isFinite ? max(seconds, 0) : 0
        let totalSeconds = safe >= Double(Int.max) ? Int.max : Int(safe.rounded(.down))
        let hours = totalSeconds / 3_600
        let minutes = totalSeconds % 3_600 / 60
        let remainingSeconds = totalSeconds % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, remainingSeconds)
        }
        return String(format: "%02d:%02d", minutes, remainingSeconds)
    }
}
