using System.Text.Json;

namespace DanLaiDanQu.Core;

public sealed class SettingsStore
{
    private static readonly JsonSerializerOptions JsonOptions = new()
    {
        WriteIndented = true,
        PropertyNameCaseInsensitive = true,
    };

    public SettingsStore(string? filePath = null)
    {
        FilePath = filePath ?? Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
            "DanLaiDanQu",
            "settings.json");
        Current = Load();
    }

    public string FilePath { get; }
    public AppSettings Current { get; }

    public void Save()
    {
        var directory = Path.GetDirectoryName(FilePath);
        if (!string.IsNullOrEmpty(directory))
        {
            Directory.CreateDirectory(directory);
        }

        var temporary = FilePath + ".tmp";
        File.WriteAllText(temporary, JsonSerializer.Serialize(Current, JsonOptions));
        File.Move(temporary, FilePath, overwrite: true);
    }

    public void RecordHistory(VideoInfo info, VideoPage page)
    {
        Current.History.RemoveAll(entry => entry.Bvid == info.Bvid && entry.Page == page.Page);
        Current.History.Insert(0, new HistoryEntry(
            info.Bvid,
            page.Page,
            info.Title,
            page.Title,
            info.Owner,
            info.DanmakuCount,
            DateTimeOffset.Now));
        if (Current.History.Count > 20)
        {
            Current.History.RemoveRange(20, Current.History.Count - 20);
        }

        Save();
    }

    private AppSettings Load()
    {
        try
        {
            if (File.Exists(FilePath))
            {
                return JsonSerializer.Deserialize<AppSettings>(File.ReadAllText(FilePath), JsonOptions) ?? new AppSettings();
            }
        }
        catch (JsonException)
        {
            // Damaged settings should not prevent the app from starting.
        }
        catch (IOException)
        {
            // Fall back to defaults when the settings directory is temporarily unavailable.
        }

        return new AppSettings();
    }
}
