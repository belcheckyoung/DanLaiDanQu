using System.Runtime.InteropServices;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Interop;
using System.Windows.Media;
using System.Windows.Media.Effects;
using System.Windows.Threading;
using DanLaiDanQu.Core;

namespace DanLaiDanQu.Windows;

public partial class OverlayWindow : Window
{
    private sealed class ActiveItem
    {
        public required TextBlock View { get; init; }
        public required Danmaku Danmaku { get; init; }
        public required double Speed { get; init; }
        public required double ExpireTime { get; init; }
    }

    private const int GwlExStyle = -20;
    private const int WsExTransparent = 0x00000020;
    private const int WsExNoActivate = 0x08000000;

    private readonly PlaybackClock _clock;
    private readonly DispatcherTimer _timer;
    private readonly List<ActiveItem> _active = [];
    private IReadOnlyList<Danmaku> _danmaku = [];
    private AppSettings _settings;
    private double[] _laneReadyAt = [];
    private int _nextIndex;
    private DateTimeOffset? _clearUntil;
    private bool _clickThrough;
    private bool _sourceInitialized;

    public OverlayWindow(PlaybackClock clock, AppSettings settings)
    {
        InitializeComponent();
        _clock = clock;
        _settings = settings;

        var area = SystemParameters.WorkArea;
        Left = area.Left;
        Top = area.Top;
        Width = area.Width;
        Height = Math.Max(area.Height * 0.42, 280);
        if (settings.OverlayPlacement is { Width: > 200, Height: > 100 } saved)
        {
            Left = saved.Left;
            Top = saved.Top;
            Width = saved.Width;
            Height = saved.Height;
        }

        SourceInitialized += (_, _) =>
        {
            _sourceInitialized = true;
            ApplyClickThrough();
        };
        SizeChanged += (_, _) => Resync();
        _timer = new DispatcherTimer(DispatcherPriority.Render)
        {
            Interval = TimeSpan.FromMilliseconds(16),
        };
        _timer.Tick += (_, _) => RenderFrame();
        _timer.Start();
        UpdatePreferences(settings);
    }

    public bool ClickThrough => _clickThrough;

    public WindowPlacement Placement => new(Left, Top, Width, Height);

    public void LoadDanmaku(IReadOnlyList<Danmaku> danmaku)
    {
        _danmaku = danmaku.OrderBy(item => item.Time).ToArray();
        Resync();
    }

    public void UpdatePreferences(AppSettings settings)
    {
        _settings = settings;
        _clickThrough = settings.MousePassthrough;
        InteractionBorder.BorderThickness = _clickThrough ? new Thickness(0) : new Thickness(2);
        ApplyClickThrough();
        Resync();
    }

    public void Resync()
    {
        ClearActive();
        RebuildLanes();
        var time = _clock.CurrentTime;
        var start = time - Math.Max(_settings.ScrollDuration, 1);
        _nextIndex = 0;
        while (_nextIndex < _danmaku.Count && _danmaku[_nextIndex].Time < start)
        {
            _nextIndex++;
        }

        while (_nextIndex < _danmaku.Count && _danmaku[_nextIndex].Time <= time)
        {
            var item = _danmaku[_nextIndex++];
            if (IsStillVisible(item, time))
            {
                Spawn(item, time);
            }
        }
    }

    public void ClearThreeSeconds()
    {
        ClearActive();
        _clearUntil = DateTimeOffset.Now.AddSeconds(3);
    }

    public void ShowCountdown(int? seconds)
    {
        if (seconds is null)
        {
            CountdownPanel.Visibility = Visibility.Collapsed;
            return;
        }

        CountdownText.Text = $"{seconds}\n弹幕即将开始，请点击视频播放";
        CountdownPanel.Visibility = Visibility.Visible;
    }

    private void RenderFrame()
    {
        if (_clearUntil is { } clearUntil)
        {
            if (DateTimeOffset.Now < clearUntil)
            {
                return;
            }

            _clearUntil = null;
            Resync();
        }

        var time = _clock.CurrentTime;
        if (_clock.IsPlaying)
        {
            while (_nextIndex < _danmaku.Count && _danmaku[_nextIndex].Time <= time)
            {
                var item = _danmaku[_nextIndex++];
                if (time - item.Time < 0.5)
                {
                    Spawn(item, time);
                }
            }
        }

        for (var index = _active.Count - 1; index >= 0; index--)
        {
            var item = _active[index];
            if (time >= item.ExpireTime)
            {
                DanmakuCanvas.Children.Remove(item.View);
                _active.RemoveAt(index);
                continue;
            }

            if (item.Danmaku.Mode == DanmakuMode.Scroll)
            {
                Canvas.SetLeft(item.View, CanvasWidth - ((time - item.Danmaku.Time) * item.Speed));
            }
        }
    }

    private void Spawn(Danmaku item, double now)
    {
        if (item.Mode == DanmakuMode.Other)
        {
            return;
        }

        RebuildLanes();
        var text = new TextBlock
        {
            Text = item.Text,
            FontFamily = new FontFamily("Microsoft YaHei UI"),
            FontSize = _settings.FontSize,
            FontWeight = FontWeights.Bold,
            Foreground = new SolidColorBrush(Color.FromRgb(
                (byte)((item.Color >> 16) & 0xFF),
                (byte)((item.Color >> 8) & 0xFF),
                (byte)(item.Color & 0xFF))),
            Opacity = Math.Clamp(_settings.Opacity, 0.1, 1.0),
            Effect = new DropShadowEffect
            {
                Color = Colors.Black,
                BlurRadius = 2,
                ShadowDepth = 1,
                Opacity = 0.95,
            },
            IsHitTestVisible = false,
        };
        text.Measure(new Size(double.PositiveInfinity, double.PositiveInfinity));
        var textWidth = Math.Max(text.DesiredSize.Width, 1);
        var lineHeight = Math.Max(_settings.FontSize * 1.35 + _settings.LaneSpacing, 24);
        var lane = AllocateLane(item.Time, lineHeight);
        var expire = item.Time + (item.Mode == DanmakuMode.Scroll ? Math.Max(_settings.ScrollDuration, 1) : 5);

        if (item.Mode == DanmakuMode.Scroll)
        {
            var speed = (CanvasWidth + textWidth) / Math.Max(_settings.ScrollDuration, 1);
            Canvas.SetLeft(text, CanvasWidth - ((now - item.Time) * speed));
            Canvas.SetTop(text, lane * lineHeight);
            _active.Add(new ActiveItem { View = text, Danmaku = item, Speed = speed, ExpireTime = expire });
        }
        else
        {
            Canvas.SetLeft(text, Math.Max((CanvasWidth - textWidth) / 2, 0));
            Canvas.SetTop(text, item.Mode == DanmakuMode.Top
                ? lane * lineHeight
                : Math.Max(CanvasHeight - ((lane + 1) * lineHeight), 0));
            _active.Add(new ActiveItem { View = text, Danmaku = item, Speed = 0, ExpireTime = expire });
        }

        DanmakuCanvas.Children.Add(text);
    }

    private int AllocateLane(double entryTime, double lineHeight)
    {
        if (_laneReadyAt.Length == 0)
        {
            RebuildLanes();
        }

        var lane = Array.FindIndex(_laneReadyAt, ready => ready <= entryTime);
        if (lane < 0)
        {
            lane = Array.IndexOf(_laneReadyAt, _laneReadyAt.Min());
        }

        _laneReadyAt[lane] = entryTime + Math.Clamp(_settings.ScrollDuration * 0.18, 0.8, 3.5);
        return lane;
    }

    private void RebuildLanes()
    {
        var lineHeight = Math.Max(_settings.FontSize * 1.35 + _settings.LaneSpacing, 24);
        var usable = CanvasHeight * Math.Clamp(_settings.DisplayAreaRatio, 0.2, 1.0);
        var count = Math.Max((int)(usable / lineHeight), 1);
        if (_laneReadyAt.Length != count)
        {
            _laneReadyAt = Enumerable.Repeat(double.NegativeInfinity, count).ToArray();
        }
    }

    private bool IsStillVisible(Danmaku item, double now)
    {
        var lifetime = item.Mode == DanmakuMode.Scroll ? Math.Max(_settings.ScrollDuration, 1) : 5;
        return now - item.Time < lifetime;
    }

    private void ClearActive()
    {
        DanmakuCanvas.Children.Clear();
        _active.Clear();
        Array.Fill(_laneReadyAt, double.NegativeInfinity);
    }

    private double CanvasWidth => Math.Max(DanmakuCanvas.ActualWidth, ActualWidth > 0 ? ActualWidth : 1200);
    private double CanvasHeight => Math.Max(DanmakuCanvas.ActualHeight, ActualHeight > 0 ? ActualHeight : 400);

    private void ApplyClickThrough()
    {
        if (!_sourceInitialized)
        {
            return;
        }

        var handle = new WindowInteropHelper(this).Handle;
        var style = GetWindowLong(handle, GwlExStyle);
        style = _clickThrough
            ? style | WsExTransparent | WsExNoActivate
            : style & ~WsExTransparent & ~WsExNoActivate;
        SetWindowLong(handle, GwlExStyle, style);
    }

    private void Window_MouseLeftButtonDown(object sender, MouseButtonEventArgs e)
    {
        if (!_clickThrough && e.ButtonState == MouseButtonState.Pressed)
        {
            DragMove();
        }
    }

    [DllImport("user32.dll")]
    private static extern int GetWindowLong(nint window, int index);

    [DllImport("user32.dll")]
    private static extern int SetWindowLong(nint window, int index, int newStyle);
}
