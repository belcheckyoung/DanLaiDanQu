using System.Text.Json;

namespace DanLaiDanQu.Core;

public sealed class DanmakuCacheStore
{
    private sealed record CacheDocument(DateTimeOffset FetchedAt, List<Danmaku> Items);

    private static readonly JsonSerializerOptions JsonOptions = new()
    {
        PropertyNameCaseInsensitive = true,
    };

    public DanmakuCacheStore(string? directory = null)
    {
        DirectoryPath = directory ?? Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
            "DanLaiDanQu",
            "cache");
    }

    public string DirectoryPath { get; }

    public IReadOnlyList<Danmaku>? TryLoad(long cid, TimeSpan? maxAge = null)
    {
        try
        {
            var path = PathFor(cid);
            if (!File.Exists(path))
            {
                return null;
            }

            var document = JsonSerializer.Deserialize<CacheDocument>(File.ReadAllText(path), JsonOptions);
            var ageLimit = maxAge ?? TimeSpan.FromHours(24);
            if (document?.Items is null || DateTimeOffset.UtcNow - document.FetchedAt > ageLimit)
            {
                return null;
            }

            return document.Items.OrderBy(item => item.Time).ToArray();
        }
        catch (JsonException)
        {
            return null;
        }
        catch (IOException)
        {
            return null;
        }
        catch (UnauthorizedAccessException)
        {
            return null;
        }
    }

    public void Save(long cid, IReadOnlyList<Danmaku> items)
    {
        try
        {
            Directory.CreateDirectory(DirectoryPath);
            var path = PathFor(cid);
            var temporary = path + ".tmp";
            var document = new CacheDocument(DateTimeOffset.UtcNow, items.ToList());
            File.WriteAllText(temporary, JsonSerializer.Serialize(document, JsonOptions));
            File.Move(temporary, path, overwrite: true);
        }
        catch (IOException)
        {
            // Cache is optional; a write failure must not block playback.
        }
        catch (UnauthorizedAccessException)
        {
        }
    }

    public void Clear()
    {
        try
        {
            if (Directory.Exists(DirectoryPath))
            {
                Directory.Delete(DirectoryPath, recursive: true);
            }
        }
        catch (IOException)
        {
        }
        catch (UnauthorizedAccessException)
        {
        }
    }

    private string PathFor(long cid) => Path.Combine(DirectoryPath, $"{cid}.json");
}
