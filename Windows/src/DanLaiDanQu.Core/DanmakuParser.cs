using System.Globalization;
using System.Xml;

namespace DanLaiDanQu.Core;

public static class DanmakuParser
{
    public static IReadOnlyList<Danmaku> Parse(byte[] xml) => Parse(new MemoryStream(xml, writable: false));

    public static IReadOnlyList<Danmaku> Parse(Stream stream)
    {
        var result = new List<Danmaku>();
        var settings = new XmlReaderSettings
        {
            DtdProcessing = DtdProcessing.Prohibit,
            IgnoreComments = true,
            IgnoreWhitespace = true,
            CloseInput = false,
        };

        try
        {
            using var reader = XmlReader.Create(stream, settings);
            while (reader.Read())
            {
                if (reader.NodeType != XmlNodeType.Element || reader.Name != "d")
                {
                    continue;
                }

                var parameters = reader.GetAttribute("p")?.Split(',');
                if (parameters is null || parameters.Length < 8)
                {
                    continue;
                }

                if (!double.TryParse(parameters[0], NumberStyles.Float, CultureInfo.InvariantCulture, out var time) ||
                    !int.TryParse(parameters[1], out var biliMode))
                {
                    continue;
                }

                _ = int.TryParse(parameters[2], out var fontSize);
                _ = uint.TryParse(parameters[3], out var color);
                _ = long.TryParse(parameters[4], out var timestamp);
                _ = int.TryParse(parameters.ElementAtOrDefault(8), out var weight);
                var text = reader.ReadString();

                result.Add(new Danmaku(
                    parameters[7],
                    Math.Max(time, 0),
                    ToMode(biliMode),
                    text,
                    color,
                    fontSize,
                    timestamp,
                    weight));
            }
        }
        catch (XmlException exception)
        {
            throw new InvalidDataException("弹幕 XML 格式无效", exception);
        }

        return result.OrderBy(item => item.Time).ToArray();
    }

    private static DanmakuMode ToMode(int mode) => mode switch
    {
        1 or 2 or 3 => DanmakuMode.Scroll,
        4 => DanmakuMode.Bottom,
        5 => DanmakuMode.Top,
        _ => DanmakuMode.Other,
    };
}
