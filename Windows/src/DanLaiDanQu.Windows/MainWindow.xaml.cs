using System.ComponentModel;
using System.Globalization;
using System.IO;
using System.Runtime.InteropServices;
using System.Security.Cryptography;
using System.Text;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Interop;
using System.Windows.Threading;
using DanLaiDanQu.Core;
using Microsoft.Win32;
using Button = System.Windows.Controls.Button;
using ComboBoxItem = System.Windows.Controls.ComboBoxItem;
using KeyEventArgs = System.Windows.Input.KeyEventArgs;
using MessageBox = System.Windows.MessageBox;
using OpenFileDialog = Microsoft.Win32.OpenFileDialog;
using SaveFileDialog = Microsoft.Win32.SaveFileDialog;
using Forms = System.Windows.Forms;

namespace DanLaiDanQu.Windows;

public partial class MainWindow : Window
{
    private const int WmHotkey = 0x0312;
    private const uint ModControl = 0x0002;
    private const uint ModShift = 0x0004;
    private const uint ModNoRepeat = 0x4000;

    private readonly BilibiliClient _client = new();
    private readonly PlaybackClock _clock = new();
    private readonly SettingsStore _settingsStore = new();
    private readonly DanmakuCacheStore _cacheStore = new();
    private readonly DispatcherTimer _uiTimer;
    private readonly List<Danmaku> _rawDanmaku = [];
    private IReadOnlyList<Danmaku> _filteredDanmaku = [];
    private AppSettings Settings => _settingsStore.Current;
    private VideoInfo? _videoInfo;
    private VideoPage? _currentPage;
    private OverlayWindow? _overlay;
    private CancellationTokenSource? _loadCancellation;
    private CancellationTokenSource? _countdownCancellation;
    private bool _isDraggingProgress;
    private bool _updatingProgress;
    private bool _updatingPage;
    private bool _updatingHistory;
    private bool _updatingRate;
    private bool _updatingDelayedStart;
    private bool _allowExit;
    private bool _isPlaybackPage;
    private bool _trayHintShown;
    private nint _windowHandle;
    private HwndSource? _windowSource;
    private Forms.NotifyIcon? _trayIcon;

    public MainWindow()
    {
        InitializeComponent();
        RestoreSettingsControls();
        RefreshHistory();
        InitializeTrayIcon();
        _uiTimer = new DispatcherTimer
        {
            Interval = TimeSpan.FromMilliseconds(100),
        };
        _uiTimer.Tick += (_, _) => RefreshPlaybackUi();
        _uiTimer.Start();
    }

    private async void LoadButton_Click(object sender, RoutedEventArgs e) => await LoadInputAsync(LinkBox.Text);

    private async void LinkBox_KeyDown(object sender, KeyEventArgs e)
    {
        if (e.Key == Key.Enter)
        {
            e.Handled = true;
            await LoadInputAsync(LinkBox.Text);
        }
    }

    private async Task LoadInputAsync(string input)
    {
        var text = input.Trim();
        if (text.Length == 0)
        {
            return;
        }

        PrepareForContentChange();
        _loadCancellation?.Cancel();
        var request = new CancellationTokenSource();
        _loadCancellation = request;
        var cancellationToken = request.Token;
        SetLoading(true, "正在获取视频信息…");

        try
        {
            if (BiliLink.IsShortLink(text))
            {
                text = await _client.ResolveShortLinkAsync(text, cancellationToken);
            }

            var link = BiliLink.Parse(text) ?? throw new InvalidOperationException("无法识别链接，请粘贴 B 站视频链接、BV 号或 av 号");
            var info = await _client.FetchVideoInfoAsync(link, cancellationToken);
            if (info.Pages.Count == 0)
            {
                throw new InvalidOperationException("该视频没有可用分 P");
            }

            var page = info.Pages.FirstOrDefault(item => item.Page == link.Page) ?? info.Pages[0];
            await LoadPageAsync(info, page, cancellationToken);
        }
        catch (OperationCanceledException)
        {
            // A newer load request replaced this one.
        }
        catch (Exception exception)
        {
            SourceStatusText.Text = exception.Message;
            PlaybackStatusText.Text = exception.Message;
        }
        finally
        {
            if (ReferenceEquals(_loadCancellation, request))
            {
                _loadCancellation = null;
                SetLoading(false, SourceStatusText.Text);
            }
            request.Dispose();
        }
    }

    private async Task LoadPageAsync(VideoInfo info, VideoPage page, CancellationToken cancellationToken)
    {
        SourceStatusText.Text = $"正在加载 P{page.Page} 弹幕…";
        var danmaku = _cacheStore.TryLoad(page.Cid);
        if (danmaku is null)
        {
            danmaku = await _client.FetchDanmakuAsync(page.Cid, cancellationToken);
            _cacheStore.Save(page.Cid, danmaku);
        }
        cancellationToken.ThrowIfCancellationRequested();

        _videoInfo = info;
        _updatingPage = true;
        PageCombo.ItemsSource = info.Pages;
        PageCombo.SelectedItem = page;
        _updatingPage = false;
        PageCombo.Visibility = info.Pages.Count > 1 ? Visibility.Visible : Visibility.Collapsed;
        _rawDanmaku.Clear();
        _rawDanmaku.AddRange(danmaku);
        _currentPage = page;
        ApplyFilters();

        _clock.Pause();
        if (Settings.SyncProfiles.TryGetValue(page.Cid.ToString(CultureInfo.InvariantCulture), out var profile))
        {
            _clock.Rate = profile.Rate;
            var restored = ClampResumePosition(profile.Offset);
            _clock.Seek(restored);
            SourceStatusText.Text = $"弹幕加载完成，已恢复到上次位置 {FormatTime(restored)}";
        }
        else
        {
            _clock.Rate = 1.0;
            _clock.Seek(0);
            SourceStatusText.Text = "弹幕加载完成";
        }

        UpdateRateCombo();
        VideoTitleText.Text = info.Title;
        VideoMetaText.Text = $"{info.Owner} · {FormatTime(page.Duration)} · 弹幕 {info.DanmakuCount} 条 · 已加载 {_rawDanmaku.Count} 条";
        VideoCard.Visibility = Visibility.Visible;
        PlaybackCard.Visibility = Visibility.Visible;
        _settingsStore.RecordHistory(info, page);
        RefreshHistory();
        ShowPlaybackPage();
        RefreshPlaybackUi();
    }

    private async void PageCombo_SelectionChanged(object sender, SelectionChangedEventArgs e)
    {
        if (_updatingPage || PageCombo.SelectedItem is not VideoPage page || page == _currentPage)
        {
            return;
        }

        _loadCancellation?.Cancel();
        PrepareForContentChange();
        var request = new CancellationTokenSource();
        _loadCancellation = request;
        try
        {
            SetLoading(true, $"正在加载 P{page.Page}…");
            await LoadPageAsync(_videoInfo!, page, request.Token);
        }
        catch (OperationCanceledException)
        {
        }
        catch (Exception exception)
        {
            SourceStatusText.Text = exception.Message;
        }
        finally
        {
            if (ReferenceEquals(_loadCancellation, request))
            {
                _loadCancellation = null;
                SetLoading(false, SourceStatusText.Text);
            }
            request.Dispose();
        }
    }

    private async void HistoryCombo_SelectionChanged(object sender, SelectionChangedEventArgs e)
    {
        if (_updatingHistory || HistoryCombo.SelectedItem is not HistoryEntry entry)
        {
            return;
        }

        LinkBox.Text = entry.Url;
        await LoadInputAsync(entry.Url);
    }

    private async void PlayButton_Click(object sender, RoutedEventArgs e)
    {
        if (_countdownCancellation is not null)
        {
            CancelCountdown();
            return;
        }

        if (_clock.IsPlaying)
        {
            _clock.Pause();
            SaveSyncProfile();
            return;
        }

        if (DelayedStartCheck.IsChecked == true)
        {
            await StartCountdownAsync(syncFromZero: false);
        }
        else
        {
            ShowOverlay();
            _clock.Play();
        }
    }

    private async void SyncButton_Click(object sender, RoutedEventArgs e)
    {
        if (_countdownCancellation is not null)
        {
            CancelCountdown();
            return;
        }

        await StartCountdownAsync(syncFromZero: true);
    }

    private async Task StartCountdownAsync(bool syncFromZero)
    {
        ShowOverlay();
        _clock.Pause();
        _countdownCancellation = new CancellationTokenSource();
        var token = _countdownCancellation.Token;
        try
        {
            for (var remaining = 5; remaining >= 1; remaining--)
            {
                _overlay?.ShowCountdown(remaining);
                PlayButton.Content = $"✕ 取消 {remaining}";
                PlayStateText.Text = $"倒计时 {remaining}s";
                await Task.Delay(TimeSpan.FromSeconds(1), token);
            }

            _overlay?.ShowCountdown(null);
            if (syncFromZero)
            {
                _clock.SyncFromNow();
                _overlay?.Resync();
            }
            else
            {
                _clock.Play();
            }
        }
        catch (OperationCanceledException)
        {
            _overlay?.ShowCountdown(null);
        }
        finally
        {
            _countdownCancellation?.Dispose();
            _countdownCancellation = null;
            RefreshPlaybackUi();
        }
    }

    private void CancelCountdown()
    {
        _countdownCancellation?.Cancel();
        _overlay?.ShowCountdown(null);
        PlaybackStatusText.Text = "已取消倒计时";
    }

    private void OverlayButton_Click(object sender, RoutedEventArgs e)
    {
        if (_overlay?.IsVisible == true)
        {
            SaveOverlayPlacement();
            _overlay.Hide();
        }
        else
        {
            ShowOverlay();
        }

        RefreshPlaybackUi();
    }

    private void ShowOverlay()
    {
        EnsureOverlay();
        if (_overlay!.IsVisible)
        {
            return;
        }

        _overlay.Show();
        _overlay.Topmost = true;
    }

    private void EnsureOverlay()
    {
        if (_overlay is not null)
        {
            return;
        }

        _overlay = new OverlayWindow(_clock, Settings);
        _overlay.LoadDanmaku(_filteredDanmaku);
    }

    private void ClearButton_Click(object sender, RoutedEventArgs e) => _overlay?.ClearThreeSeconds();

    private void DelayedStartCheck_Changed(object sender, RoutedEventArgs e)
    {
        if (_updatingDelayedStart || !IsInitialized)
        {
            return;
        }
        Settings.DelayedStart = DelayedStartCheck.IsChecked == true;
        _settingsStore.Save();
    }

    private void RateCombo_SelectionChanged(object sender, SelectionChangedEventArgs e)
    {
        if (_updatingRate || RateCombo.SelectedItem is not ComboBoxItem { Tag: string value } ||
            !double.TryParse(value, NumberStyles.Float, CultureInfo.InvariantCulture, out var rate))
        {
            return;
        }
        _clock.Rate = rate;
        _overlay?.Resync();
        SaveSyncProfile();
    }

    private void SaveProfileButton_Click(object sender, RoutedEventArgs e)
    {
        SaveSyncProfile();
        PlaybackStatusText.Text = "已保存当前进度，下次打开此视频自动恢复";
    }

    private void AdjustButton_Click(object sender, RoutedEventArgs e)
    {
        if (sender is Button { Tag: string value } && double.TryParse(value, NumberStyles.Float, CultureInfo.InvariantCulture, out var delta))
        {
            Seek(_clock.CurrentTime + delta);
        }
    }

    private void ApplyOffsetButton_Click(object sender, RoutedEventArgs e)
    {
        var text = OffsetBox.Text.Trim().TrimEnd('s', 'S', '秒').TrimStart('+');
        if (double.TryParse(text, NumberStyles.Float, CultureInfo.InvariantCulture, out var delta))
        {
            Seek(_clock.CurrentTime + delta);
            OffsetBox.Clear();
        }
    }

    private void ProgressSlider_PreviewMouseLeftButtonDown(object sender, MouseButtonEventArgs e) => _isDraggingProgress = true;

    private void ProgressSlider_PreviewMouseLeftButtonUp(object sender, MouseButtonEventArgs e)
    {
        if (_isDraggingProgress)
        {
            Seek(ProgressSlider.Value);
        }

        _isDraggingProgress = false;
    }

    private void ProgressSlider_ValueChanged(object sender, RoutedPropertyChangedEventArgs<double> e)
    {
        if (_isDraggingProgress && !_updatingProgress)
        {
            Seek(ProgressSlider.Value);
            DurationText.Text = $"{FormatTime(ProgressSlider.Value)} / {FormatTime(TotalDuration)}";
        }
    }

    private void Seek(double time)
    {
        _clock.Seek(ClampToDuration(time));
        _overlay?.Resync();
        RefreshPlaybackUi();
    }

    private double ClampToDuration(double time)
    {
        var duration = TotalDuration;
        return duration > 0 ? Math.Clamp(time, 0, duration) : Math.Max(time, 0);
    }

    private double ClampResumePosition(double time)
    {
        var duration = TotalDuration;
        var maximum = duration > 1 ? duration - 1 : 0;
        return duration > 0 ? Math.Clamp(time, 0, maximum) : Math.Max(time, 0);
    }

    private void SettingsButton_Click(object sender, RoutedEventArgs e)
    {
        RestoreSettingsControls();
        SettingsPage.Visibility = Visibility.Visible;
    }

    private void SettingsBackButton_Click(object sender, RoutedEventArgs e) => SettingsPage.Visibility = Visibility.Collapsed;

    private void SaveSettingsButton_Click(object sender, RoutedEventArgs e)
    {
        var filters = FilterEngine.ParseFilterText(KeywordsBox.Text);
        var invalidRegexes = FilterEngine.InvalidRegexPatterns(filters.Regexes);
        if (invalidRegexes.Count > 0)
        {
            MessageBox.Show(this, $"以下正则表达式无效：\n{string.Join("\n", invalidRegexes)}",
                "无法保存设置", MessageBoxButton.OK, MessageBoxImage.Warning);
            return;
        }

        Settings.FontSize = FontSizeSlider.Value;
        Settings.Opacity = OpacitySlider.Value / 100.0;
        Settings.ScrollDuration = ScrollDurationSlider.Value;
        Settings.DisplayAreaRatio = DisplayAreaSlider.Value / 100.0;
        Settings.MaxPerSecond = DensityCombo.SelectedItem is ComboBoxItem { Tag: string density } && int.TryParse(density, out var parsedDensity)
            ? parsedDensity
            : 0;
        Settings.DelayedStart = DelayedStartCheck.IsChecked == true;
        Settings.MousePassthrough = MousePassthroughCheck.IsChecked == true;
        Settings.Rules.ShowTop = ShowTopCheck.IsChecked == true;
        Settings.Rules.ShowBottom = ShowBottomCheck.IsChecked == true;
        Settings.Rules.BlockColored = ShowColorCheck.IsChecked != true;
        Settings.Rules.MergeDuplicates = MergeDuplicatesCheck.IsChecked == true;
        Settings.Rules.Keywords = filters.Keywords;
        Settings.Rules.RegexPatterns = filters.Regexes;
        _settingsStore.Save();
        ApplyFilters();
        _overlay?.UpdatePreferences(Settings);
        SettingsPage.Visibility = Visibility.Collapsed;
        PlaybackStatusText.Text = "设置已保存";
    }

    private void RestoreSettingsControls()
    {
        FontSizeSlider.Value = Settings.FontSize;
        OpacitySlider.Value = Settings.Opacity * 100;
        ScrollDurationSlider.Value = Settings.ScrollDuration;
        DisplayAreaSlider.Value = Settings.DisplayAreaRatio * 100;
        DensityCombo.SelectedIndex = Settings.MaxPerSecond switch
        {
            30 => 1,
            20 => 2,
            10 => 3,
            5 => 4,
            _ => 0,
        };
        KeywordsBox.Text = string.Join(", ", Settings.Rules.Keywords.Concat(Settings.Rules.RegexPatterns.Select(pattern => $"/{pattern}/")));
        ShowTopCheck.IsChecked = Settings.Rules.ShowTop;
        ShowBottomCheck.IsChecked = Settings.Rules.ShowBottom;
        ShowColorCheck.IsChecked = !Settings.Rules.BlockColored;
        MergeDuplicatesCheck.IsChecked = Settings.Rules.MergeDuplicates;
        MousePassthroughCheck.IsChecked = Settings.MousePassthrough;
        _updatingDelayedStart = true;
        DelayedStartCheck.IsChecked = Settings.DelayedStart;
        _updatingDelayedStart = false;
        UpdateSettingsValueLabels();
    }

    private void UpdateRateCombo()
    {
        _updatingRate = true;
        var rateText = _clock.Rate.ToString(CultureInfo.InvariantCulture);
        RateCombo.SelectedItem = RateCombo.Items.OfType<ComboBoxItem>()
            .FirstOrDefault(item => string.Equals(item.Tag?.ToString(), rateText, StringComparison.Ordinal));
        RateCombo.SelectedIndex = RateCombo.SelectedIndex >= 0 ? RateCombo.SelectedIndex : 2;
        _updatingRate = false;
    }

    private void SettingsSlider_ValueChanged(object sender, RoutedPropertyChangedEventArgs<double> e)
    {
        if (IsInitialized)
        {
            UpdateSettingsValueLabels();
        }
    }

    private void UpdateSettingsValueLabels()
    {
        if (FontSizeValue is null || OpacityValue is null || ScrollDurationValue is null || DisplayAreaValue is null)
        {
            return;
        }

        FontSizeValue.Text = $"{FontSizeSlider.Value:0} pt";
        OpacityValue.Text = $"{OpacitySlider.Value:0}%";
        ScrollDurationValue.Text = $"{ScrollDurationSlider.Value:0} 秒";
        DisplayAreaValue.Text = $"{DisplayAreaSlider.Value:0}%";
    }

    private void ApplyFilters()
    {
        var filtered = FilterEngine.Apply(_rawDanmaku, Settings.Rules);
        _filteredDanmaku = FilterEngine.Downsample(filtered, Settings.MaxPerSecond);
        _overlay?.LoadDanmaku(_filteredDanmaku);
    }

    private void ImportXmlButton_Click(object sender, RoutedEventArgs e)
    {
        var dialog = new OpenFileDialog
        {
            Title = "导入弹幕 XML",
            Filter = "Bilibili 弹幕 XML (*.xml)|*.xml|所有文件 (*.*)|*.*",
        };
        if (dialog.ShowDialog(this) != true)
        {
            return;
        }

        try
        {
            var items = DanmakuParser.Parse(File.ReadAllBytes(dialog.FileName));
            PrepareForContentChange();
            var duration = items.Count > 0 ? Math.Max((int)Math.Ceiling(items[^1].Time), 60) : 0;
            var page = new VideoPage(LocalCid(dialog.FileName), 1, "本地弹幕", duration);
            var info = new VideoInfo(
                $"local-{Math.Abs(page.Cid)}",
                0,
                Path.GetFileNameWithoutExtension(dialog.FileName),
                "本地导入",
                duration,
                [page],
                items.Count);

            _videoInfo = info;
            _currentPage = page;
            _rawDanmaku.Clear();
            _rawDanmaku.AddRange(items);
            ApplyFilters();
            _updatingPage = true;
            PageCombo.ItemsSource = info.Pages;
            PageCombo.SelectedItem = page;
            PageCombo.Visibility = Visibility.Collapsed;
            _updatingPage = false;
            RestorePageProgress(page);
            VideoTitleText.Text = info.Title;
            VideoMetaText.Text = $"本地导入 · {FormatTime(duration)} · 已加载 {items.Count} 条";
            SourceStatusText.Text = items.Count == 0 ? "XML 格式有效，但文件中没有弹幕" : "本地弹幕导入成功";
            PlaybackStatusText.Text = SourceStatusText.Text;
            ShowPlaybackPage();
            RefreshPlaybackUi();
        }
        catch (Exception exception) when (exception is IOException or InvalidDataException or UnauthorizedAccessException)
        {
            MessageBox.Show(this, exception.Message, "导入失败", MessageBoxButton.OK, MessageBoxImage.Error);
        }
    }

    private void ExportButton_Click(object sender, RoutedEventArgs e)
    {
        if (_rawDanmaku.Count == 0 || sender is not Button { Tag: string format })
        {
            PlaybackStatusText.Text = "请先加载弹幕";
            return;
        }

        var extension = format.ToLowerInvariant();
        var dialog = new SaveFileDialog
        {
            Title = $"导出 {extension.ToUpperInvariant()}",
            Filter = $"{extension.ToUpperInvariant()} 文件 (*.{extension})|*.{extension}",
            FileName = $"{SafeFileName(_videoInfo?.Title ?? "danmaku")}.{extension}",
            AddExtension = true,
            DefaultExt = extension,
        };
        if (dialog.ShowDialog(this) != true)
        {
            return;
        }

        try
        {
            var items = FilterEngine.Apply(_rawDanmaku, Settings.Rules);
            var data = extension switch
            {
                "xml" => DanmakuExporter.ExportXml(items, _currentPage?.Cid ?? 0),
                "ass" => DanmakuExporter.ExportAss(items, _videoInfo?.Title ?? "Danmaku"),
                "json" => DanmakuExporter.ExportJson(items),
                _ => throw new InvalidOperationException("不支持的导出格式"),
            };
            File.WriteAllBytes(dialog.FileName, data);
            PlaybackStatusText.Text = $"已导出 {Path.GetFileName(dialog.FileName)}";
        }
        catch (Exception exception) when (exception is IOException or UnauthorizedAccessException)
        {
            MessageBox.Show(this, exception.Message, "导出失败", MessageBoxButton.OK, MessageBoxImage.Error);
        }
    }

    private void DeleteHistoryButton_Click(object sender, RoutedEventArgs e)
    {
        if (HistoryCombo.SelectedItem is not HistoryEntry selected)
        {
            return;
        }
        Settings.History.RemoveAll(entry => entry.Bvid == selected.Bvid && entry.Page == selected.Page);
        _settingsStore.Save();
        RefreshHistory();
    }

    private void ClearHistoryButton_Click(object sender, RoutedEventArgs e)
    {
        if (MessageBox.Show(this, "确定清空最近观看记录和弹幕缓存吗？", "清空记录",
                MessageBoxButton.YesNo, MessageBoxImage.Question) != MessageBoxResult.Yes)
        {
            return;
        }
        Settings.History.Clear();
        _settingsStore.Save();
        _cacheStore.Clear();
        RefreshHistory();
    }

    private void BackToSourceButton_Click(object sender, RoutedEventArgs e)
    {
        SaveSyncProfile();
        _clock.Pause();
        _isPlaybackPage = false;
        SourceCard.Visibility = Visibility.Visible;
        HistoryCard.Visibility = !_isPlaybackPage && Settings.History.Count > 0
            ? Visibility.Visible
            : Visibility.Collapsed;
        VideoCard.Visibility = Visibility.Collapsed;
        PlaybackCard.Visibility = Visibility.Collapsed;
        LinkBox.Focus();
    }

    private void ShowPlaybackPage()
    {
        _isPlaybackPage = true;
        SourceCard.Visibility = Visibility.Collapsed;
        HistoryCard.Visibility = Visibility.Collapsed;
        VideoCard.Visibility = Visibility.Visible;
        PlaybackCard.Visibility = Visibility.Visible;
    }

    private void PrepareForContentChange()
    {
        if (_countdownCancellation is not null)
        {
            CancelCountdown();
        }
        SaveSyncProfile();
        _clock.Pause();
    }

    private void RestorePageProgress(VideoPage page)
    {
        _clock.Pause();
        if (Settings.SyncProfiles.TryGetValue(page.Cid.ToString(CultureInfo.InvariantCulture), out var profile))
        {
            _clock.Rate = profile.Rate;
            _clock.Seek(ClampResumePosition(profile.Offset));
        }
        else
        {
            _clock.Rate = 1;
            _clock.Seek(0);
        }
        UpdateRateCombo();
    }

    private static long LocalCid(string path)
    {
        var bytes = SHA256.HashData(Encoding.UTF8.GetBytes(Path.GetFullPath(path).ToUpperInvariant()));
        var value = BitConverter.ToInt64(bytes, 0) & long.MaxValue;
        return -Math.Max(value, 1);
    }

    private static string SafeFileName(string value)
    {
        var invalid = Path.GetInvalidFileNameChars();
        var cleaned = new string(value.Select(character => invalid.Contains(character) ? '-' : character).ToArray()).Trim();
        return string.IsNullOrWhiteSpace(cleaned) ? "danmaku" : cleaned;
    }

    private void SaveSyncProfile()
    {
        if (_currentPage is null)
        {
            return;
        }

        Settings.SyncProfiles[_currentPage.Cid.ToString(CultureInfo.InvariantCulture)] = new SyncProfile(_clock.CurrentTime, _clock.Rate);
        SaveOverlayPlacement();
        _settingsStore.Save();
    }

    private void SaveOverlayPlacement()
    {
        if (_overlay is not null)
        {
            Settings.OverlayPlacement = _overlay.Placement;
        }
    }

    private void RefreshHistory()
    {
        _updatingHistory = true;
        HistoryCombo.ItemsSource = null;
        HistoryCombo.ItemsSource = Settings.History;
        HistoryCombo.SelectedIndex = -1;
        HistoryCard.Visibility = !_isPlaybackPage && Settings.History.Count > 0
            ? Visibility.Visible
            : Visibility.Collapsed;
        _updatingHistory = false;
    }

    private void SetLoading(bool loading, string message)
    {
        LoadButton.IsEnabled = !loading;
        LinkBox.IsEnabled = !loading;
        SourceStatusText.Text = message;
    }

    private void RefreshPlaybackUi()
    {
        var time = Math.Max(_clock.CurrentTime, 0);
        var duration = TotalDuration;
        var playing = _clock.IsPlaying;
        if (playing && duration > 0 && time >= duration)
        {
            _clock.Seek(duration);
            _clock.Pause();
            SaveSyncProfile();
            time = duration;
            playing = false;
            PlaybackStatusText.Text = "已播放到片尾";
        }
        if (_countdownCancellation is null)
        {
            PlayButton.Content = playing ? "⏸ 暂停" : "▶ 播放";
        }

        CurrentTimeText.Text = $"{(playing ? "▶" : "⏸")} {FormatTime(time)}";
        DurationText.Text = $"{FormatTime(time)} / {FormatTime(duration)}";
        TimelineStateText.Text = $"{FormatTime(time)} / {FormatTime(duration)}";
        PlayStateText.Text = _countdownCancellation is not null ? PlayStateText.Text : playing ? "播放中" : "已暂停";
        OverlayStateText.Text = _overlay?.IsVisible == true
            ? Settings.MousePassthrough ? "穿透已开" : "可拖动"
            : "弹幕层未打开";
        CountStateText.Text = $"{_filteredDanmaku.Count} 条";
        OverlayButton.Content = _overlay?.IsVisible == true ? "关闭弹幕层" : "打开弹幕层";

        ProgressSlider.IsEnabled = duration > 0;
        if (!_isDraggingProgress && duration > 0)
        {
            _updatingProgress = true;
            ProgressSlider.Maximum = duration;
            ProgressSlider.Value = Math.Min(time, duration);
            _updatingProgress = false;
        }
    }

    private double TotalDuration => _currentPage is { Duration: > 0 }
        ? _currentPage.Duration
        : _rawDanmaku.Count > 0 ? Math.Max(Math.Ceiling(_rawDanmaku[^1].Time), 60) : 0;

    private static string FormatTime(double seconds)
    {
        return TimelineFormatter.Format(seconds);
    }

    private void Window_SourceInitialized(object? sender, EventArgs e)
    {
        _windowHandle = new WindowInteropHelper(this).Handle;
        _windowSource = HwndSource.FromHwnd(_windowHandle);
        _windowSource?.AddHook(WindowProc);
        var registrations = new[]
        {
            RegisterHotKey(_windowHandle, 1, ModControl | ModShift | ModNoRepeat, 0x20), // Space
            RegisterHotKey(_windowHandle, 2, ModControl | ModShift | ModNoRepeat, 0x25), // Left
            RegisterHotKey(_windowHandle, 3, ModControl | ModShift | ModNoRepeat, 0x27), // Right
            RegisterHotKey(_windowHandle, 4, ModControl | ModShift | ModNoRepeat, 0x28), // Down
            RegisterHotKey(_windowHandle, 5, ModControl | ModShift | ModNoRepeat, 0x26), // Up
            RegisterHotKey(_windowHandle, 6, ModControl | ModShift | ModNoRepeat, 0x30), // 0
            RegisterHotKey(_windowHandle, 7, ModControl | ModShift | ModNoRepeat, 0x48), // H
        };
        if (registrations.Any(success => !success))
        {
            SourceStatusText.Text = "部分全局快捷键已被其他软件占用";
        }
    }

    private nint WindowProc(nint hwnd, int message, nint wParam, nint lParam, ref bool handled)
    {
        if (message != WmHotkey)
        {
            return 0;
        }

        handled = true;
        switch (wParam.ToInt32())
        {
            case 1:
                if (_clock.IsPlaying)
                {
                    _clock.Pause();
                    SaveSyncProfile();
                }
                else
                {
                    ShowOverlay();
                    _clock.Play();
                }
                break;
            case 2: Seek(_clock.CurrentTime - 1); break;
            case 3: Seek(_clock.CurrentTime + 1); break;
            case 4: Seek(_clock.CurrentTime - 5); break;
            case 5: Seek(_clock.CurrentTime + 5); break;
            case 6: ShowOverlay(); _clock.SyncFromNow(); _overlay?.Resync(); break;
            case 7: OverlayButton_Click(this, new RoutedEventArgs()); break;
        }

        return 0;
    }

    private void InitializeTrayIcon()
    {
        var menu = new Forms.ContextMenuStrip();
        menu.Items.Add("显示主窗口", null, (_, _) => Dispatcher.Invoke(ShowMainWindow));
        menu.Items.Add("打开 / 关闭弹幕层", null, (_, _) => Dispatcher.Invoke(() => OverlayButton_Click(this, new RoutedEventArgs())));
        menu.Items.Add("播放 / 暂停弹幕", null, (_, _) => Dispatcher.Invoke(TogglePlaybackFromTray));
        menu.Items.Add(new Forms.ToolStripSeparator());
        menu.Items.Add("退出", null, (_, _) => Dispatcher.Invoke(ExitApplication));

        _trayIcon = new Forms.NotifyIcon
        {
            Icon = System.Drawing.SystemIcons.Application,
            Text = "弹来弹去",
            Visible = true,
            ContextMenuStrip = menu,
        };
        _trayIcon.DoubleClick += (_, _) => Dispatcher.Invoke(ShowMainWindow);
    }

    private void ShowMainWindow()
    {
        Show();
        WindowState = WindowState.Normal;
        Activate();
    }

    private void TogglePlaybackFromTray()
    {
        if (_clock.IsPlaying)
        {
            _clock.Pause();
            SaveSyncProfile();
        }
        else
        {
            ShowOverlay();
            _clock.Play();
        }
        RefreshPlaybackUi();
    }

    private void ExitApplication()
    {
        _allowExit = true;
        Close();
    }

    private void Window_Closing(object? sender, CancelEventArgs e)
    {
        if (!_allowExit)
        {
            SaveSyncProfile();
            SaveOverlayPlacement();
            _settingsStore.Save();
            e.Cancel = true;
            Hide();
            if (!_trayHintShown)
            {
                _trayIcon?.ShowBalloonTip(2500, "弹来弹去仍在运行", "可通过系统托盘继续控制或退出。", Forms.ToolTipIcon.Info);
                _trayHintShown = true;
            }
            return;
        }

        _loadCancellation?.Cancel();
        _countdownCancellation?.Cancel();
        SaveSyncProfile();
        SaveOverlayPlacement();
        _settingsStore.Save();
        _uiTimer.Stop();
        for (var id = 1; id <= 7; id++)
        {
            UnregisterHotKey(_windowHandle, id);
        }

        _windowSource?.RemoveHook(WindowProc);
        _overlay?.Close();
        if (_trayIcon is not null)
        {
            _trayIcon.Visible = false;
            _trayIcon.Dispose();
            _trayIcon = null;
        }
    }

    [DllImport("user32.dll")]
    private static extern bool RegisterHotKey(nint window, int id, uint modifiers, uint virtualKey);

    [DllImport("user32.dll")]
    private static extern bool UnregisterHotKey(nint window, int id);
}
