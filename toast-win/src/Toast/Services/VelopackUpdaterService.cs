using Toast.Core.Services;
using Toast.Helpers;
using Velopack;
using Velopack.Sources;

namespace Toast.Services;

public sealed class UpdateAvailableEventArgs : EventArgs
{
    public required string Version { get; init; }
    public required bool FromManualCheck { get; init; }
}

public sealed class VelopackUpdaterService : IUpdaterService
{
    private const string SkippedVersionKey = "updateSkippedVersion";
    private const string SkippedUntilKey = "updateSkippedUntil";
    private static readonly TimeSpan FirstCheckDelay = TimeSpan.FromSeconds(25);
    private static readonly TimeSpan PeriodicInterval = TimeSpan.FromHours(6);
    private static readonly TimeSpan SkipDuration = TimeSpan.FromDays(7);

    private readonly IPreferencesStore _prefs;
    private readonly UpdateManager? _manager;
    private readonly object _gate = new();
    private UpdateInfo? _pending;
    private CancellationTokenSource? _bgCts;
    private bool _promptOpen;
    private bool _checking;

    public VelopackUpdaterService(AppConfig config, IPreferencesStore prefs)
    {
        _prefs = prefs;
        try
        {
            var source = new GithubSource(config.UpdateUrl, "", prerelease: false);
            _manager = new UpdateManager(source);
        }
        catch
        {
            _manager = null;
        }
    }

    public bool SupportsManualUpdates => _manager?.IsInstalled == true;

    public string? PendingVersion
    {
        get
        {
            lock (_gate)
            {
                return VersionOf(_pending);
            }
        }
    }

    public event EventHandler<UpdateAvailableEventArgs>? UpdateAvailable;

    public void StartBackgroundChecks()
    {
        if (!SupportsManualUpdates)
        {
            return;
        }

        _bgCts?.Cancel();
        _bgCts = new CancellationTokenSource();
        _ = RunBackgroundLoopAsync(_bgCts.Token);
    }

    public void StopBackgroundChecks()
    {
        _bgCts?.Cancel();
        _bgCts = null;
    }

    /// <summary>Manual "Check for updates" — ignores skip snooze and always offers Download &amp; restart.</summary>
    /// <returns>True if an update was found and the prompt was offered.</returns>
    public async Task<bool> CheckForUpdatesAsync()
    {
        var result = await CheckInternalAsync(respectSkip: false);
        if (result is null)
        {
            return false;
        }

        OfferUpdate(result, fromManualCheck: true);
        return true;
    }

    public async Task DownloadAndRestartAsync()
    {
        UpdateInfo? update;
        lock (_gate)
        {
            update = _pending;
        }

        if (_manager is null || update is null)
        {
            // Re-check in case the prompt was opened without a cached package.
            update = await CheckInternalAsync(respectSkip: false);
            if (update is null)
            {
                return;
            }
        }

        ClearSkip();
        await _manager!.DownloadUpdatesAsync(update);
        _manager.ApplyUpdatesAndRestart(update);
    }

    public void SkipPendingVersion()
    {
        string? version;
        lock (_gate)
        {
            version = VersionOf(_pending);
            _pending = null;
            _promptOpen = false;
        }

        if (string.IsNullOrWhiteSpace(version))
        {
            return;
        }

        _prefs.SetString(SkippedVersionKey, version);
        _prefs.SetString(SkippedUntilKey, DateTimeOffset.UtcNow.Add(SkipDuration).ToString("O"));
    }

    public void MarkPromptClosed()
    {
        lock (_gate)
        {
            _promptOpen = false;
        }
    }

    private async Task RunBackgroundLoopAsync(CancellationToken ct)
    {
        try
        {
            await Task.Delay(FirstCheckDelay, ct);
            while (!ct.IsCancellationRequested)
            {
                try
                {
                    var update = await CheckInternalAsync(respectSkip: true);
                    if (update is not null)
                    {
                        OfferUpdate(update, fromManualCheck: false);
                    }
                }
                catch
                {
                    // Network / update failures must never break the tray app.
                }

                await Task.Delay(PeriodicInterval, ct);
            }
        }
        catch (OperationCanceledException)
        {
            // Expected on quit.
        }
    }

    private void OfferUpdate(UpdateInfo update, bool fromManualCheck)
    {
        var version = VersionOf(update);
        if (string.IsNullOrWhiteSpace(version))
        {
            return;
        }

        lock (_gate)
        {
            _pending = update;
            if (_promptOpen)
            {
                return;
            }

            _promptOpen = true;
        }

        UpdateAvailable?.Invoke(this, new UpdateAvailableEventArgs
        {
            Version = version,
            FromManualCheck = fromManualCheck,
        });
    }

    private async Task<UpdateInfo?> CheckInternalAsync(bool respectSkip)
    {
        if (_manager is null || !_manager.IsInstalled)
        {
            return null;
        }

        lock (_gate)
        {
            if (_checking)
            {
                return null;
            }

            _checking = true;
        }

        try
        {
            var update = await _manager.CheckForUpdatesAsync();
            if (update is null)
            {
                return null;
            }

            var version = VersionOf(update);
            if (respectSkip && IsSkipped(version))
            {
                return null;
            }

            lock (_gate)
            {
                _pending = update;
            }

            return update;
        }
        finally
        {
            lock (_gate)
            {
                _checking = false;
            }
        }
    }

    private bool IsSkipped(string? version)
    {
        if (string.IsNullOrWhiteSpace(version))
        {
            return false;
        }

        var skipped = _prefs.GetString(SkippedVersionKey);
        if (!string.Equals(skipped, version, StringComparison.OrdinalIgnoreCase))
        {
            return false;
        }

        var untilRaw = _prefs.GetString(SkippedUntilKey);
        if (untilRaw is null || !DateTimeOffset.TryParse(untilRaw, out var until))
        {
            ClearSkip();
            return false;
        }

        if (DateTimeOffset.UtcNow >= until)
        {
            ClearSkip();
            return false;
        }

        return true;
    }

    private void ClearSkip()
    {
        _prefs.SetString(SkippedVersionKey, null);
        _prefs.SetString(SkippedUntilKey, null);
    }

    private static string? VersionOf(UpdateInfo? update)
    {
        try
        {
            return update?.TargetFullRelease?.Version?.ToString();
        }
        catch
        {
            return null;
        }
    }
}
