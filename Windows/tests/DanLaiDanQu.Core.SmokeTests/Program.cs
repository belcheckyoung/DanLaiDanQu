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

var xml = "<?xml version=\"1.0\"?><i><d p=\"1.5,1,25,16777215,1,0,u,id,5\">hello &amp; world</d><d p=\"2,5,25,16711680,2,0,u,id2,3\">top</d></i>";
var parsed = DanmakuParser.Parse(Encoding.UTF8.GetBytes(xml));
Check(parsed.Count == 2, "XML parsing count failed");
Check(parsed[0].Text == "hello & world" && parsed[1].Mode == DanmakuMode.Top, "XML parsing fields failed");

var rules = new FilterRules { Keywords = ["block"], MergeDuplicates = true };
var filtered = FilterEngine.Apply([
    new Danmaku("1", 1, DanmakuMode.Scroll, "keep", 0xFFFFFF, 25, 0, 0),
    new Danmaku("2", 2, DanmakuMode.Scroll, "BLOCK this", 0xFFFFFF, 25, 0, 0),
    new Danmaku("3", 3, DanmakuMode.Scroll, "keep", 0xFFFFFF, 25, 0, 0),
], rules);
Check(filtered.Count == 1, "filtering and duplicate merging failed");

var tokens = FilterEngine.ParseFilterText("广告，/哈{3,}/, spoiler");
Check(tokens.Keywords.SequenceEqual(["广告", "spoiler"]) && tokens.Regexes.SequenceEqual(["哈{3,}"]), "filter tokenization failed");

if (failures.Count > 0)
{
    Console.Error.WriteLine($"FAILED ({failures.Count})");
    foreach (var failure in failures)
    {
        Console.Error.WriteLine($"- {failure}");
    }

    return 1;
}

Console.WriteLine("Windows core smoke tests passed (BiliLink, PlaybackClock, DanmakuParser, FilterEngine).");
return 0;
