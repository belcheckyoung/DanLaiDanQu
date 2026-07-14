using System.ComponentModel;
using System.Globalization;
using System.Runtime.InteropServices;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Interop;
using System.Windows.Threading;
using DanLaiDanQu.Core;

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
    private nint _windowHandle;
    private HwndSource? _windowSource;

    public MainWindow()
    {
        InitializeComponent();
        RestoreSettingsControls();
        RefreshHistory();
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

        _loadCancellation?.Cancel();
        _loadCancellation = new CancellationTokenSource();
        var cancellationToken = _loadCancellation.Token;
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

            _videoInfo = info;
            _updatingPage = true;
            PageCombo.ItemsSource = info.Pages;
            var page = info.Pages.FirstOrDefault(item => item.Page == link.Page) ?? info.Pages[0];
            PageCombo.SelectedItem = page;
            _updatingPage = false;
            PageCombo.Visibility = info.Pages.Count > 1 ? Visibility.Visible : Visibility.Collapsed;
            await LoadPageAsync(page, cancellationToken);
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
            SetLoading(false, SourceStatusText.Text);
        }
    }

    private async Task LoadPageAsync(VideoPage page, CancellationToken cancellationToken)
    {
        if (_videoInfo is null)
        {
            return;
        }

        SourceStatusText.Text = $"正在加载 P{page.Page} 弹幕…";
        var danmaku = await _client.FetchDanmakuAsync(page.Cid, cancellationToken);
        _rawDanmaku.Clear();
        _rawDanmaku.AddRange(danmaku);
        _currentPage = page;
        ApplyFilters();

        _clock.Pause();
        if (Settings.SyncProfiles.TryGetValue(page.Cid.ToString(CultureInfo.InvariantCulture), out var profile))
        {
            _clock.Rate = profile.Rate;
            _clock.Seek(ClampToDuration(profile.Offset));
            SourceStatusText.Text = $"弹幕加载完成，已恢复到上次位置 {FormatTime(profile.Offset)}";
        }
        else
        {
            _clock.Rate = 1.0;
            _clock.Seek(0);
            SourceStatusText.Text = "弹幕加载完成";
        }

        VideoTitleText.Text = _videoInfo.Title;
        VideoMetaText.Text = $"{_videoInfo.Owner} · {FormatTime(page.Duration)} · 弹幕 {_videoInfo.DanmakuCount} 条 · 已加载 {_rawDanmaku.Count} 条";
        VideoCard.Visibility = Visibility.Visible;
        PlaybackCard.Visibility = Visibility.Visible;
        _settingsStore.RecordHistory(_videoInfo, page);
        RefreshHistory();
        RefreshPlaybackUi();
    }

    private async void PageCombo_SelectionChanged(object sender, SelectionChangedEventArgs e)
    {
        if (_updatingPage || PageCombo.SelectedItem is not VideoPage page || page == _currentPage)
        {
            return;
        }

        _loadCancellation?.Cancel();
        _loadCancellation = new CancellationTokenSource();
        try
        {
            SetLoading(true, $"正在加载 P{page.Page}…");
            await LoadPageAsync(page, _loadCancellation.Token);
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
            SetLoading(false, SourceStatusText.Text);
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

    private void SettingsButton_Click(object sender, RoutedEventArgs e)
    {
        RestoreSettingsControls();
        SettingsPage.Visibility = Visibility.Visible;
    }

    private void SettingsBackButton_Click(object sender, RoutedEventArgs e) => SettingsPage.Visibility = Visibility.Collapsed;

    private void SaveSettingsButton_Click(object sender, RoutedEventArgs e)
    {
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
        var filters = FilterEngine.ParseFilterText(KeywordsBox.Text);
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
        DelayedStartCheck.IsChecked = Settings.DelayedStart;
        UpdateSettingsValueLabels();
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
        HistoryCard.Visibility = Settings.History.Count > 0 ? Visibility.Visible : Visibility.Collapsed;
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
        if (_countdownCancellation is null)
        {
            PlayButton.Content = playing ? "⏸ 暂停" : "▶ 播放";
        }

        CurrentTimeText.Text = $"{(playing ? "▶" : "⏸")} {FormatTimeTenths(time)}";
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
        var safe = Math.Max(seconds, 0);
        return $"{(int)safe / 60:00}:{(int)safe % 60:00}";
    }

    private static string FormatTimeTenths(double seconds)
    {
        var safe = Math.Max(seconds, 0);
        return $"{(int)safe / 60:00}:{(int)safe % 60:00}.{(int)(safe * 10) % 10}";
    }

    private void Window_SourceInitialized(object? sender, EventArgs e)
    {
        _windowHandle = new WindowInteropHelper(this).Handle;
        _windowSource = HwndSource.FromHwnd(_windowHandle);
        _windowSource?.AddHook(WindowProc);
        RegisterHotKey(_windowHandle, 1, ModControl | ModShift | ModNoRepeat, 0x20); // Space
        RegisterHotKey(_windowHandle, 2, ModControl | ModShift | ModNoRepeat, 0x25); // Left
        RegisterHotKey(_windowHandle, 3, ModControl | ModShift | ModNoRepeat, 0x27); // Right
        RegisterHotKey(_windowHandle, 4, ModControl | ModShift | ModNoRepeat, 0x28); // Down
        RegisterHotKey(_windowHandle, 5, ModControl | ModShift | ModNoRepeat, 0x26); // Up
        RegisterHotKey(_windowHandle, 6, ModControl | ModShift | ModNoRepeat, 0x30); // 0
        RegisterHotKey(_windowHandle, 7, ModControl | ModShift | ModNoRepeat, 0x48); // H
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
                if (_clock.IsPlaying) _clock.Pause(); else { ShowOverlay(); _clock.Play(); }
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

    private void Window_Closing(object? sender, CancelEventArgs e)
    {
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
    }

    [DllImport("user32.dll")]
    private static extern bool RegisterHotKey(nint window, int id, uint modifiers, uint virtualKey);

    [DllImport("user32.dll")]
    private static extern bool UnregisterHotKey(nint window, int id);
}
