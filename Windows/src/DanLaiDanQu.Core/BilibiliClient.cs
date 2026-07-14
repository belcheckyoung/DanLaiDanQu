using System.IO.Compression;
using System.Net;
using System.Net.Http.Headers;
using System.Text.Json;

namespace DanLaiDanQu.Core;

public sealed class BilibiliClient
{
    private readonly HttpClient _client;

    public BilibiliClient(HttpMessageHandler? handler = null)
    {
        handler ??= new HttpClientHandler
        {
            AllowAutoRedirect = true,
            AutomaticDecompression = DecompressionMethods.All,
            UseCookies = false,
        };
        _client = new HttpClient(handler)
        {
            Timeout = TimeSpan.FromSeconds(20),
        };
        _client.DefaultRequestHeaders.UserAgent.ParseAdd(
            "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/124.0 Safari/537.36");
        _client.DefaultRequestHeaders.Referrer = new Uri("https://www.bilibili.com/");
        _client.DefaultRequestHeaders.AcceptEncoding.Add(new StringWithQualityHeaderValue("gzip"));
        _client.DefaultRequestHeaders.AcceptEncoding.Add(new StringWithQualityHeaderValue("deflate"));
        _client.DefaultRequestHeaders.AcceptEncoding.Add(new StringWithQualityHeaderValue("br"));
    }

    public async Task<string> ResolveShortLinkAsync(string input, CancellationToken cancellationToken = default)
    {
        var match = System.Text.RegularExpressions.Regex.Match(input, @"https?://b23\.tv/\S+", System.Text.RegularExpressions.RegexOptions.IgnoreCase);
        if (!match.Success || !Uri.TryCreate(match.Value, UriKind.Absolute, out var uri))
        {
            throw new InvalidOperationException("无法识别短链接");
        }

        using var response = await _client.GetAsync(uri, HttpCompletionOption.ResponseHeadersRead, cancellationToken);
        response.EnsureSuccessStatusCode();
        return response.RequestMessage?.RequestUri?.ToString() ?? input;
    }

    public async Task<VideoInfo> FetchVideoInfoAsync(BiliLink link, CancellationToken cancellationToken = default)
    {
        var query = link switch
        {
            BiliLink.Bvid bvid => $"bvid={Uri.EscapeDataString(bvid.Id)}",
            BiliLink.Avid avid => $"aid={avid.Id}",
            _ => throw new ArgumentOutOfRangeException(nameof(link)),
        };
        using var document = await GetJsonAsync($"https://api.bilibili.com/x/web-interface/view?{query}", cancellationToken);
        var root = document.RootElement;
        var code = root.TryGetProperty("code", out var codeNode) ? codeNode.GetInt32() : -1;
        if (code != 0 || !root.TryGetProperty("data", out var data))
        {
            var message = root.TryGetProperty("message", out var messageNode) ? messageNode.GetString() : "未知错误";
            throw new InvalidOperationException($"B 站接口返回错误（{code}）：{message}");
        }

        var pages = new List<VideoPage>();
        if (data.TryGetProperty("pages", out var pagesNode))
        {
            foreach (var page in pagesNode.EnumerateArray())
            {
                var number = page.GetProperty("page").GetInt32();
                pages.Add(new VideoPage(
                    page.GetProperty("cid").GetInt64(),
                    number,
                    page.TryGetProperty("part", out var part) ? part.GetString() ?? $"P{number}" : $"P{number}",
                    page.TryGetProperty("duration", out var duration) ? duration.GetInt32() : 0));
            }
        }

        var owner = data.TryGetProperty("owner", out var ownerNode) && ownerNode.TryGetProperty("name", out var nameNode)
            ? nameNode.GetString() ?? string.Empty
            : string.Empty;
        var danmakuCount = data.TryGetProperty("stat", out var statNode) && statNode.TryGetProperty("danmaku", out var countNode)
            ? countNode.GetInt32()
            : 0;

        return new VideoInfo(
            data.TryGetProperty("bvid", out var bvidNode) ? bvidNode.GetString() ?? string.Empty : string.Empty,
            data.TryGetProperty("aid", out var aidNode) ? aidNode.GetInt64() : 0,
            data.TryGetProperty("title", out var titleNode) ? titleNode.GetString() ?? string.Empty : string.Empty,
            owner,
            data.TryGetProperty("duration", out var durationNode) ? durationNode.GetInt32() : 0,
            pages,
            danmakuCount);
    }

    public async Task<IReadOnlyList<Danmaku>> FetchDanmakuAsync(long cid, CancellationToken cancellationToken = default)
    {
        using var response = await _client.GetAsync($"https://api.bilibili.com/x/v1/dm/list.so?oid={cid}", cancellationToken);
        response.EnsureSuccessStatusCode();
        var payload = await response.Content.ReadAsByteArrayAsync(cancellationToken);
        var xml = InflateIfNeeded(payload);
        return DanmakuParser.Parse(xml);
    }

    private async Task<JsonDocument> GetJsonAsync(string url, CancellationToken cancellationToken)
    {
        using var response = await _client.GetAsync(url, cancellationToken);
        response.EnsureSuccessStatusCode();
        await using var stream = await response.Content.ReadAsStreamAsync(cancellationToken);
        return await JsonDocument.ParseAsync(stream, cancellationToken: cancellationToken);
    }

    internal static byte[] InflateIfNeeded(byte[] payload)
    {
        if (payload.Length == 0 || payload.SkipWhile(value => char.IsWhiteSpace((char)value)).FirstOrDefault() == '<')
        {
            return payload;
        }

        return TryInflate(payload, zlib: true) ?? TryInflate(payload, zlib: false) ?? payload;
    }

    private static byte[]? TryInflate(byte[] payload, bool zlib)
    {
        try
        {
            using var input = new MemoryStream(payload, writable: false);
            using Stream decompressor = zlib
                ? new ZLibStream(input, CompressionMode.Decompress)
                : new DeflateStream(input, CompressionMode.Decompress);
            using var output = new MemoryStream();
            decompressor.CopyTo(output);
            return output.ToArray();
        }
        catch (InvalidDataException)
        {
            return null;
        }
    }
}
