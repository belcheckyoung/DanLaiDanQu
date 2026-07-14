using System.Text;
using DanLaiDanQu.Core;

var failures = new List<string>();

void Check(bool condition, string message)
{
    if (!condition)
    {
        failures.Add(message);
    }
}

var bvid = BiliLink.Parse("https://www.bilibili.com/video/BV1xx411c7mD?p=3");
Check(bvid is BiliLink.Bvid { Id: "BV1xx411c7mD", Page: 3 }, "BV and page parsing failed");
Check(BiliLink.Parse("av170001?p=2") is BiliLink.Avid { Id: 170001, Page: 2 }, "av parsing failed");
Check(BiliLink.Parse("not a bilibili link") is null, "invalid links should be rejected");

var now = 0L;
var clock = new PlaybackClock(() => now, frequency: 10);
clock.Seek(12.5);
clock.Play();
now = 20;
Check(Math.Abs(clock.CurrentTime - 14.5) < 0.001, "playback clock progression failed");
clock.Pause();
now = 100;
Check(Math.Abs(clock.CurrentTime - 14.5) < 0.001, "paused clock should not progress");
clock.Seek(-5);
Check(clock.CurrentTime == 0, "negative seek should clamp to zero");

Check(TimelineFormatter.Format(29 * 60 + 39.8) == "29:39", "timeline should drop fractional seconds");
Check(TimelineFormatter.Format(3_599.9) == "59:59", "sub-hour timeline formatting failed");
Check(TimelineFormatter.Format(3_600) == "1:00:00", "one-hour timeline formatting failed");
Check(TimelineFormatter.Format(2 * 3_600 + 30) == "2:00:30", "multi-hour timeline formatting failed");
Check(TimelineFormatter.Format(-1) == "00:00" && TimelineFormatter.Format(double.PositiveInfinity) == "00:00",
    "invalid timeline values should clamp to zero");

var xml = "<?xml version=\"1.0\"?><i><d p=\"1.5,1,25,16777215,1,0,u,id,5\">hello &amp; world</d><d p=\"2,5,25,16711680,2,0,u,id2,3\">top</d></i>";
var parsed = DanmakuParser.Parse(Encoding.UTF8.GetBytes(xml));
Check(parsed.Count == 2, "XML parsing count failed");
Check(parsed[0].Text == "hello & world" && parsed[1].Mode == DanmakuMode.Top, "XML parsing fields failed");
var malformedRejected = false;
try
{
    _ = DanmakuParser.Parse(Encoding.UTF8.GetBytes("<i><d p=\"1,1,25,1,1,0,u,id\">broken"));
}
catch (InvalidDataException)
{
    malformedRejected = true;
}
Check(malformedRejected, "malformed XML should fail instead of returning an empty success");

var rules = new FilterRules { Keywords = ["block"], MergeDuplicates = true };
var filtered = FilterEngine.Apply([
    new Danmaku("1", 1, DanmakuMode.Scroll, "keep", 0xFFFFFF, 25, 0, 0),
    new Danmaku("2", 2, DanmakuMode.Scroll, "BLOCK this", 0xFFFFFF, 25, 0, 0),
    new Danmaku("3", 3, DanmakuMode.Scroll, "keep", 0xFFFFFF, 25, 0, 0),
], rules);
Check(filtered.Count == 1, "filtering and duplicate merging failed");

var tokens = FilterEngine.ParseFilterText("广告，/哈{3,}/, spoiler");
Check(tokens.Keywords.SequenceEqual(["广告", "spoiler"]) && tokens.Regexes.SequenceEqual(["哈{3,}"]), "filter tokenization failed");
Check(FilterEngine.InvalidRegexPatterns(["[broken"]).Count == 1, "invalid regex validation failed");

var temporaryDirectory = Path.Combine(Path.GetTempPath(), $"DanLaiDanQu-tests-{Guid.NewGuid():N}");
try
{
    var cache = new DanmakuCacheStore(Path.Combine(temporaryDirectory, "cache"));
    cache.Save(123, parsed);
    Check(cache.TryLoad(123)?.Count == 2, "danmaku cache roundtrip failed");

    var exportedXml = Encoding.UTF8.GetString(DanmakuExporter.ExportXml(parsed, 123));
    var exportedAss = Encoding.UTF8.GetString(DanmakuExporter.ExportAss(parsed, "test"));
    Check(exportedXml.Contains("hello &amp; world") && exportedXml.Contains("<chatid>123</chatid>"), "XML export failed");
    Check(exportedAss.Contains("[Events]") && exportedAss.Contains("Dialogue:"), "ASS export failed");

    var settingsPath = Path.Combine(temporaryDirectory, "settings.json");
    Directory.CreateDirectory(temporaryDirectory);
    File.WriteAllText(settingsPath, "{\"Rules\":null,\"History\":null,\"SyncProfiles\":null,\"Opacity\":9}");
    var settings = new SettingsStore(settingsPath).Current;
    Check(settings.Rules is not null && settings.History is not null && settings.SyncProfiles is not null,
        "settings normalization failed");
    Check(Math.Abs(settings.Opacity - 1) < 0.001, "settings range normalization failed");
}
finally
{
    if (Directory.Exists(temporaryDirectory))
    {
        Directory.Delete(temporaryDirectory, recursive: true);
    }
}

if (failures.Count > 0)
{
    Console.Error.WriteLine($"FAILED ({failures.Count})");
    foreach (var failure in failures)
    {
        Console.Error.WriteLine($"- {failure}");
    }

    return 1;
}

Console.WriteLine("Windows core smoke tests passed (BiliLink, PlaybackClock, TimelineFormatter, DanmakuParser, FilterEngine).");
return 0;
