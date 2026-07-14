using System.Globalization;
using System.Text;
using System.Text.Encodings.Web;
using System.Text.Json;

namespace DanLaiDanQu.Core;

public static class DanmakuExporter
{
    public static byte[] ExportJson(IReadOnlyList<Danmaku> items) => JsonSerializer.SerializeToUtf8Bytes(items, new JsonSerializerOptions
    {
        WriteIndented = true,
        Encoder = JavaScriptEncoder.UnsafeRelaxedJsonEscaping,
    });

    public static byte[] ExportXml(IReadOnlyList<Danmaku> items, long cid)
    {
        var output = new StringBuilder($"<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<i>\n<chatid>{cid}</chatid>\n");
        foreach (var item in items)
        {
            var mode = item.Mode switch
            {
                DanmakuMode.Bottom => 4,
                DanmakuMode.Top => 5,
                DanmakuMode.Other => 7,
                _ => 1,
            };
            var parameters = FormattableString.Invariant($"{item.Time},{mode},{item.FontSize},{item.Color},{item.Timestamp},0,0,{item.Id}");
            output.Append("<d p=\"").Append(parameters).Append("\">")
                .Append(EscapeXml(item.Text)).Append("</d>\n");
        }

        output.Append("</i>\n");
        return Encoding.UTF8.GetBytes(output.ToString());
    }

    public static byte[] ExportAss(IReadOnlyList<Danmaku> items, string title, int width = 1920, int height = 1080)
    {
        const int fontSize = 48;
        const double scrollDuration = 12;
        const double fixedDuration = 5;
        var output = new StringBuilder();
        output.AppendLine("[Script Info]")
            .AppendLine($"Title: {title.Replace("\n", " ")}")
            .AppendLine("ScriptType: v4.00+")
            .AppendLine($"PlayResX: {width}")
            .AppendLine($"PlayResY: {height}")
            .AppendLine("WrapStyle: 2")
            .AppendLine("ScaledBorderAndShadow: yes")
            .AppendLine()
            .AppendLine("[V4+ Styles]")
            .AppendLine("Format: Name, Fontname, Fontsize, PrimaryColour, SecondaryColour, OutlineColour, BackColour, Bold, Italic, Underline, StrikeOut, ScaleX, ScaleY, Spacing, Angle, BorderStyle, Outline, Shadow, Alignment, MarginL, MarginR, MarginV, Encoding")
            .AppendLine($"Style: Danmaku,Microsoft YaHei UI,{fontSize},&H00FFFFFF,&H00FFFFFF,&H00000000,&H00000000,0,0,0,0,100,100,0,0,1,1.5,0,7,0,0,0,1")
            .AppendLine()
            .AppendLine("[Events]")
            .AppendLine("Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text");

        var scrollFree = Enumerable.Repeat(0d, 14).ToArray();
        var topFree = Enumerable.Repeat(0d, 5).ToArray();
        var bottomFree = Enumerable.Repeat(0d, 5).ToArray();
        var laneHeight = height / 14;
        foreach (var item in items.Where(item => item.Mode != DanmakuMode.Other).OrderBy(item => item.Time))
        {
            var color = item.Color == 0xFFFFFF
                ? string.Empty
                : $"{{\\c&H{item.Color & 0xFF:X2}{(item.Color >> 8) & 0xFF:X2}{(item.Color >> 16) & 0xFF:X2}&}}";
            var text = color + EscapeAss(item.Text);
            switch (item.Mode)
            {
                case DanmakuMode.Scroll:
                {
                    var lane = Array.FindIndex(scrollFree, ready => ready <= item.Time);
                    if (lane < 0) continue;
                    var textWidth = EstimateWidth(item.Text, fontSize);
                    scrollFree[lane] = item.Time + scrollDuration * textWidth / (width + textWidth) + 0.3;
                    var move = $"{{\\move({width + textWidth / 2},{lane * laneHeight},{-textWidth / 2},{lane * laneHeight})}}";
                    AppendAssLine(output, item.Time, item.Time + scrollDuration, move + text);
                    break;
                }
                case DanmakuMode.Top:
                {
                    var lane = Array.FindIndex(topFree, ready => ready <= item.Time);
                    if (lane < 0) continue;
                    topFree[lane] = item.Time + fixedDuration;
                    AppendAssLine(output, item.Time, item.Time + fixedDuration, $"{{\\an8\\pos({width / 2},{lane * laneHeight})}}{text}");
                    break;
                }
                case DanmakuMode.Bottom:
                {
                    var lane = Array.FindIndex(bottomFree, ready => ready <= item.Time);
                    if (lane < 0) continue;
                    bottomFree[lane] = item.Time + fixedDuration;
                    AppendAssLine(output, item.Time, item.Time + fixedDuration, $"{{\\an2\\pos({width / 2},{height - 40 - lane * laneHeight})}}{text}");
                    break;
                }
            }
        }

        return Encoding.UTF8.GetBytes(output.ToString());
    }

    private static void AppendAssLine(StringBuilder output, double start, double end, string text) =>
        output.Append("Dialogue: 0,").Append(AssTime(start)).Append(',').Append(AssTime(end))
            .Append(",Danmaku,,0,0,0,,").Append(text).AppendLine();

    private static string AssTime(double value)
    {
        value = Math.Max(value, 0);
        var whole = (int)value;
        return string.Create(CultureInfo.InvariantCulture, $"{whole / 3600}:{whole % 3600 / 60:00}:{whole % 60:00}.{(int)((value - Math.Floor(value)) * 100):00}");
    }

    private static int EstimateWidth(string text, int fontSize) => (int)(text.EnumerateRunes().Sum(rune => rune.Value > 0x2E80 ? 1.0 : 0.55) * fontSize);

    private static string EscapeXml(string text) => text.Replace("&", "&amp;").Replace("<", "&lt;").Replace(">", "&gt;");

    private static string EscapeAss(string text) => text.Replace("\\", "\\\\").Replace("{", "(").Replace("}", ")").Replace("\r", " ").Replace("\n", " ");
}
