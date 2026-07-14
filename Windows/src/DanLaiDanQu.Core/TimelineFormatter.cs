namespace DanLaiDanQu.Core;

public static class TimelineFormatter
{
    public static string Format(double seconds)
    {
        var safe = double.IsFinite(seconds) ? Math.Max(seconds, 0) : 0;
        var totalSeconds = safe >= long.MaxValue ? long.MaxValue : (long)Math.Floor(safe);
        var hours = totalSeconds / 3_600;
        var minutes = totalSeconds % 3_600 / 60;
        var remainingSeconds = totalSeconds % 60;

        return hours > 0
            ? $"{hours}:{minutes:00}:{remainingSeconds:00}"
            : $"{minutes:00}:{remainingSeconds:00}";
    }
}
