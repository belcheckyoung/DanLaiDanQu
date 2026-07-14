using System.Text.RegularExpressions;

namespace DanLaiDanQu.Core;

public enum DanmakuMode
{
    Scroll,
    Top,
    Bottom,
    Other,
}

public sealed record Danmaku(
    string Id,
    double Time,
    DanmakuMode Mode,
    string Text,
    uint Color,
    int FontSize,
    long Timestamp,
    int Weight);

public sealed record VideoPage(long Cid, int Page, string Title, int Duration)
{
    public string DisplayTitle => $"P{Page} {Title}";
}

public sealed record VideoInfo(
    string Bvid,
    long Aid,
    string Title,
    string Owner,
    int Duration,
    IReadOnlyList<VideoPage> Pages,
    int DanmakuCount);

public abstract record BiliLink(int Page)
{
    private static readonly Regex PagePattern = new(@"[?&]p=(\d+)", RegexOptions.IgnoreCase | RegexOptions.Compiled);
    private static readonly Regex BvidPattern = new(@"BV[0-9A-Za-z]{10}", RegexOptions.Compiled);
    private static readonly Regex AvidPattern = new(@"(?:av|AV)(\d+)", RegexOptions.Compiled);

    public sealed record Bvid(string Id, int RequestedPage) : BiliLink(RequestedPage);
    public sealed record Avid(long Id, int RequestedPage) : BiliLink(RequestedPage);

    public static BiliLink? Parse(string input)
    {
        var text = input.Trim();
        if (text.Length == 0)
        {
            return null;
        }

        var page = 1;
        var pageMatch = PagePattern.Match(text);
        if (pageMatch.Success && int.TryParse(pageMatch.Groups[1].Value, out var parsedPage) && parsedPage > 0)
        {
            page = parsedPage;
        }

        var bvid = BvidPattern.Match(text);
        if (bvid.Success)
        {
            return new Bvid(bvid.Value, page);
        }

        var avid = AvidPattern.Match(text);
        if (avid.Success && long.TryParse(avid.Groups[1].Value, out var aid))
        {
            return new Avid(aid, page);
        }

        return null;
    }

    public static bool IsShortLink(string input) => input.Contains("b23.tv/", StringComparison.OrdinalIgnoreCase);
}

public sealed class FilterRules
{
    public List<string> Keywords { get; set; } = [];
    public List<string> RegexPatterns { get; set; } = [];
    public bool BlockColored { get; set; }
    public int MaxLength { get; set; }
    public bool MergeDuplicates { get; set; } = true;
    public bool ShowTop { get; set; } = true;
    public bool ShowBottom { get; set; } = true;
    public double DuplicateWindow { get; set; } = 20;
}

public sealed record SyncProfile(double Offset, double Rate);

public sealed record HistoryEntry(
    string Bvid,
    int Page,
    string Title,
    string PartTitle,
    string Owner,
    int DanmakuCount,
    DateTimeOffset LastOpenedAt)
{
    public string DisplayTitle => $"{Title} · P{Page} {PartTitle}";
    public string Url => $"https://www.bilibili.com/video/{Bvid}?p={Page}";
}

public sealed class AppSettings
{
    public double FontSize { get; set; } = 28;
    public double Opacity { get; set; } = 0.9;
    public double ScrollDuration { get; set; } = 12;
    public double DisplayAreaRatio { get; set; } = 1.0;
    public int MaxPerSecond { get; set; }
    public double LaneSpacing { get; set; } = 4;
    public bool MousePassthrough { get; set; } = true;
    public bool DelayedStart { get; set; } = true;
    public FilterRules Rules { get; set; } = new();
    public Dictionary<string, SyncProfile> SyncProfiles { get; set; } = [];
    public List<HistoryEntry> History { get; set; } = [];
    public WindowPlacement? OverlayPlacement { get; set; }
}

public sealed record WindowPlacement(double Left, double Top, double Width, double Height);
