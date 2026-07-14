using System.Text.RegularExpressions;

namespace DanLaiDanQu.Core;

public static class FilterEngine
{
    public static IReadOnlyList<Danmaku> Apply(IEnumerable<Danmaku> source, FilterRules rules)
    {
        var regexes = rules.RegexPatterns
            .Select(pattern => TryRegex(pattern))
            .Where(regex => regex is not null)
            .Cast<Regex>()
            .ToArray();
        var lastSeen = new Dictionary<string, double>(StringComparer.Ordinal);
        var result = new List<Danmaku>();

        foreach (var item in source)
        {
            if (item.Mode == DanmakuMode.Other ||
                (!rules.ShowTop && item.Mode == DanmakuMode.Top) ||
                (!rules.ShowBottom && item.Mode == DanmakuMode.Bottom) ||
                (rules.BlockColored && item.Color != 0xFFFFFF) ||
                (rules.MaxLength > 0 && item.Text.Length > rules.MaxLength) ||
                rules.Keywords.Any(keyword => item.Text.Contains(keyword, StringComparison.OrdinalIgnoreCase)) ||
                regexes.Any(regex => IsMatchSafe(regex, item.Text)))
            {
                continue;
            }

            if (rules.MergeDuplicates)
            {
                if (lastSeen.TryGetValue(item.Text, out var last) && item.Time - last < rules.DuplicateWindow)
                {
                    continue;
                }

                lastSeen[item.Text] = item.Time;
            }

            result.Add(item);
        }

        return result;
    }

    public static IReadOnlyList<Danmaku> Downsample(IEnumerable<Danmaku> source, int maxPerSecond)
    {
        if (maxPerSecond <= 0)
        {
            return source.ToArray();
        }

        var buckets = new Dictionary<int, int>();
        var result = new List<Danmaku>();
        foreach (var item in source)
        {
            var second = (int)item.Time;
            buckets.TryGetValue(second, out var count);
            if (count >= maxPerSecond)
            {
                continue;
            }

            buckets[second] = count + 1;
            result.Add(item);
        }

        return result;
    }

    public static (List<string> Keywords, List<string> Regexes) ParseFilterText(string text)
    {
        var keywords = new List<string>();
        var regexes = new List<string>();
        var token = new List<char>();
        var inRegex = false;
        var escaped = false;

        void AddToken()
        {
            var value = new string(token.ToArray()).Trim();
            token.Clear();
            if (value.Length == 0)
            {
                return;
            }

            if (value.Length > 2 && value.StartsWith('/') && value.EndsWith('/'))
            {
                regexes.Add(value[1..^1]);
            }
            else
            {
                keywords.Add(value);
            }
        }

        foreach (var character in text)
        {
            if ((character == ',' || character == '，') && !inRegex)
            {
                AddToken();
                escaped = false;
                continue;
            }

            if (character == '/' && !escaped)
            {
                inRegex = !inRegex;
            }

            token.Add(character);
            escaped = character == '\\' && !escaped;
            if (character != '\\')
            {
                escaped = false;
            }
        }

        AddToken();
        return (keywords, regexes);
    }

    public static IReadOnlyList<string> InvalidRegexPatterns(IEnumerable<string> patterns) => patterns
        .Where(pattern => TryRegex(pattern) is null)
        .ToArray();

    private static bool IsMatchSafe(Regex regex, string text)
    {
        try
        {
            return regex.IsMatch(text);
        }
        catch (RegexMatchTimeoutException)
        {
            // 用户规则不应使 UI 线程崩溃；超时内容按命中处理并屏蔽。
            return true;
        }
    }

    private static Regex? TryRegex(string pattern)
    {
        try
        {
            return new Regex(pattern, RegexOptions.IgnoreCase | RegexOptions.CultureInvariant, TimeSpan.FromMilliseconds(100));
        }
        catch (ArgumentException)
        {
            return null;
        }
    }
}
