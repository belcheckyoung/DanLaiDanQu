using System.Diagnostics;

namespace DanLaiDanQu.Core;

public sealed class PlaybackClock
{
    private readonly object _gate = new();
    private readonly Func<long> _timestamp;
    private readonly double _frequency;
    private double _baseTime;
    private long _baseTimestamp;
    private double _rate = 1.0;

    public PlaybackClock(Func<long>? timestamp = null, long? frequency = null)
    {
        _timestamp = timestamp ?? Stopwatch.GetTimestamp;
        _frequency = frequency ?? Stopwatch.Frequency;
        _baseTimestamp = _timestamp();
    }

    public event Action? Changed;

    public bool IsPlaying { get; private set; }

    public double Rate
    {
        get
        {
            lock (_gate)
            {
                return _rate;
            }
        }
        set
        {
            lock (_gate)
            {
                var now = _timestamp();
                _baseTime = CurrentTimeUnsafe(now);
                _baseTimestamp = now;
                _rate = Math.Clamp(value, 0.1, 4.0);
            }

            Changed?.Invoke();
        }
    }

    public double CurrentTime
    {
        get
        {
            lock (_gate)
            {
                return CurrentTimeUnsafe(_timestamp());
            }
        }
    }

    public void Play()
    {
        lock (_gate)
        {
            if (IsPlaying)
            {
                return;
            }

            _baseTimestamp = _timestamp();
            IsPlaying = true;
        }

        Changed?.Invoke();
    }

    public void Pause()
    {
        lock (_gate)
        {
            if (!IsPlaying)
            {
                return;
            }

            var now = _timestamp();
            _baseTime = CurrentTimeUnsafe(now);
            _baseTimestamp = now;
            IsPlaying = false;
        }

        Changed?.Invoke();
    }

    public void Toggle()
    {
        if (IsPlaying)
        {
            Pause();
        }
        else
        {
            Play();
        }
    }

    public void Seek(double time)
    {
        lock (_gate)
        {
            _baseTime = Math.Max(time, 0);
            _baseTimestamp = _timestamp();
        }

        Changed?.Invoke();
    }

    public void Adjust(double delta) => Seek(CurrentTime + delta);

    public void SyncFromNow()
    {
        lock (_gate)
        {
            _baseTime = 0;
            _baseTimestamp = _timestamp();
            IsPlaying = true;
        }

        Changed?.Invoke();
    }

    private double CurrentTimeUnsafe(long now)
    {
        if (!IsPlaying)
        {
            return _baseTime;
        }

        return _baseTime + ((now - _baseTimestamp) / _frequency * _rate);
    }
}
