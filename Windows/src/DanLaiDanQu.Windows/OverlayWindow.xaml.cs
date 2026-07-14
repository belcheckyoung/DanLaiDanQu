using System.Runtime.InteropServices;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Interop;
using System.Windows.Media;
using System.Windows.Media.Effects;
using System.Windows.Threading;
using DanLaiDanQu.Core;
using MediaColor = System.Windows.Media.Color;
using MediaFontFamily = System.Windows.Media.FontFamily;
using WpfSize = System.Windows.Size;

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

    private readonly record struct ScrollLaneState(double EntryTime, double Width, double Speed);

    private const int GwlExStyle = -20;
    private const int WsExTransparent = 0x00000020;
    private const int WsExNoActivate = 0x08000000;

    private readonly PlaybackClock _clock;
    private readonly DispatcherTimer _timer;
    private readonly List<ActiveItem> _active = [];
    private IReadOnlyList<Danmaku> _danmaku = [];
    private AppSettings _settings;
    private ScrollLaneState[] _scrollLanes = [];
    private double[] _topLaneReadyAt = [];
    private double[] _bottomLaneReadyAt = [];
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
        if (settings.OverlayPlacement is { Width: > 200, Height: > 100 } saved && IsPlacementVisible(saved))
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
            ClearActive();
            RebuildLanes();
            var resumeTime = _clock.CurrentTime;
            _nextIndex = 0;
            while (_nextIndex < _danmaku.Count && _danmaku[_nextIndex].Time <= resumeTime)
            {
                _nextIndex++;
            }
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
            FontFamily = new MediaFontFamily("Microsoft YaHei UI"),
            FontSize = _settings.FontSize,
            FontWeight = FontWeights.Bold,
            Foreground = new SolidColorBrush(MediaColor.FromRgb(
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
        text.Measure(new WpfSize(double.PositiveInfinity, double.PositiveInfinity));
        var textWidth = Math.Max(text.DesiredSize.Width, 1);
        var lineHeight = Math.Max(_settings.FontSize * 1.35 + _settings.LaneSpacing, 24);
        var expire = item.Time + (item.Mode == DanmakuMode.Scroll ? Math.Max(_settings.ScrollDuration, 1) : 5);

        if (item.Mode == DanmakuMode.Scroll)
        {
            var speed = (CanvasWidth + textWidth) / Math.Max(_settings.ScrollDuration, 1);
            var lane = AllocateScrollLane(item.Time, textWidth, speed);
            if (lane is null)
            {
                return;
            }
            Canvas.SetLeft(text, CanvasWidth - ((now - item.Time) * speed));
            Canvas.SetTop(text, lane.Value * lineHeight);
            _active.Add(new ActiveItem { View = text, Danmaku = item, Speed = speed, ExpireTime = expire });
        }
        else
        {
            var lane = AllocateFixedLane(item.Mode, item.Time);
            if (lane is null)
            {
                return;
            }
            Canvas.SetLeft(text, Math.Max((CanvasWidth - textWidth) / 2, 0));
            Canvas.SetTop(text, item.Mode == DanmakuMode.Top
                ? lane.Value * lineHeight
                : Math.Max(CanvasHeight - ((lane.Value + 1) * lineHeight), 0));
            _active.Add(new ActiveItem { View = text, Danmaku = item, Speed = 0, ExpireTime = expire });
        }

        DanmakuCanvas.Children.Add(text);
    }

    private int? AllocateScrollLane(double entryTime, double width, double speed)
    {
        if (_scrollLanes.Length == 0)
        {
            RebuildLanes();
        }

        int? best = null;
        var bestSlack = double.NegativeInfinity;
        for (var index = 0; index < _scrollLanes.Length; index++)
        {
            var lane = _scrollLanes[index];
            if (double.IsNegativeInfinity(lane.EntryTime))
            {
                best = index;
                break;
            }

            var elapsed = entryTime - lane.EntryTime;
            var tailCleared = lane.Speed * elapsed >= lane.Width;
            var previousExit = lane.EntryTime + ((CanvasWidth + lane.Width) / Math.Max(lane.Speed, 1));
            var noCatchUp = speed <= lane.Speed || (previousExit - entryTime) * speed <= CanvasWidth;
            if (tailCleared && noCatchUp && elapsed > bestSlack)
            {
                best = index;
                bestSlack = elapsed;
            }
        }

        if (best is not null)
        {
            _scrollLanes[best.Value] = new ScrollLaneState(entryTime, width, speed);
        }
        return best;
    }

    private int? AllocateFixedLane(DanmakuMode mode, double entryTime)
    {
        var lanes = mode == DanmakuMode.Top ? _topLaneReadyAt : _bottomLaneReadyAt;
        var lane = Array.FindIndex(lanes, ready => ready <= entryTime);
        if (lane < 0)
        {
            return null;
        }
        lanes[lane] = entryTime + 5;
        return lane;
    }

    private void RebuildLanes()
    {
        var lineHeight = Math.Max(_settings.FontSize * 1.35 + _settings.LaneSpacing, 24);
        var usable = CanvasHeight * Math.Clamp(_settings.DisplayAreaRatio, 0.2, 1.0);
        var count = Math.Max((int)(usable / lineHeight), 1);
        if (_scrollLanes.Length != count)
        {
            _scrollLanes = Enumerable.Repeat(
                new ScrollLaneState(double.NegativeInfinity, 0, 0), count).ToArray();
        }
        var fixedCount = Math.Max(count / 2, 1);
        if (_topLaneReadyAt.Length != fixedCount)
        {
            _topLaneReadyAt = Enumerable.Repeat(double.NegativeInfinity, fixedCount).ToArray();
            _bottomLaneReadyAt = Enumerable.Repeat(double.NegativeInfinity, fixedCount).ToArray();
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
        Array.Fill(_scrollLanes, new ScrollLaneState(double.NegativeInfinity, 0, 0));
        Array.Fill(_topLaneReadyAt, double.NegativeInfinity);
        Array.Fill(_bottomLaneReadyAt, double.NegativeInfinity);
    }

    private static bool IsPlacementVisible(WindowPlacement placement)
    {
        var left = SystemParameters.VirtualScreenLeft;
        var top = SystemParameters.VirtualScreenTop;
        var right = left + SystemParameters.VirtualScreenWidth;
        var bottom = top + SystemParameters.VirtualScreenHeight;
        return placement.Left + placement.Width > left + 80 &&
               placement.Top + placement.Height > top + 80 &&
               placement.Left < right - 80 &&
               placement.Top < bottom - 80;
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
