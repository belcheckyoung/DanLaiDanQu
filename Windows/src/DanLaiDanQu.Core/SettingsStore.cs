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
                return Normalize(JsonSerializer.Deserialize<AppSettings>(File.ReadAllText(FilePath), JsonOptions) ?? new AppSettings());
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
        catch (UnauthorizedAccessException)
        {
            // Fall back to defaults when the settings file is not accessible.
        }

        return new AppSettings();
    }

    private static AppSettings Normalize(AppSettings settings)
    {
        settings.Rules ??= new FilterRules();
        settings.Rules.Keywords ??= [];
        settings.Rules.RegexPatterns ??= [];
        settings.SyncProfiles ??= [];
        settings.History ??= [];
        settings.FontSize = Math.Clamp(settings.FontSize, 14, 60);
        settings.Opacity = Math.Clamp(settings.Opacity, 0.1, 1.0);
        settings.ScrollDuration = Math.Clamp(settings.ScrollDuration, 4, 24);
        settings.DisplayAreaRatio = Math.Clamp(settings.DisplayAreaRatio, 0.2, 1.0);
        settings.MaxPerSecond = settings.MaxPerSecond is 0 or 5 or 10 or 20 or 30 ? settings.MaxPerSecond : 0;
        settings.LaneSpacing = Math.Clamp(settings.LaneSpacing, 0, 20);
        if (settings.History.Count > 20)
        {
            settings.History = settings.History.Take(20).ToList();
        }
        return settings;
    }
}
