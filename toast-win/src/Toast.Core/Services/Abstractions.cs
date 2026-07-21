namespace Toast.Core.Services;

public interface ITokenStore
{
    bool HasToken();
    string? LoadToken();
    void SaveToken(string token);
    void DeleteToken();
}

public interface IPreferencesStore
{
    bool GetBool(string key, bool defaultValue);
    void SetBool(string key, bool value);
    string? GetString(string key);
    void SetString(string key, string? value);
    T? GetJson<T>(string key);
    void SetJson<T>(string key, T? value);
}

public interface INotificationService
{
    Task RequestAuthorizationAsync();
    Task NotifyAsync(string title, string body);
}

public interface IAnalyticsService
{
    bool IsEnabled { get; set; }
    void StartIfNeeded();
    void Stop();
    void TrackAppLaunch();
    void Capture(string eventName, IReadOnlyDictionary<string, object>? properties = null);
    void CaptureSettingChanged(string setting, bool value);
    void CapturePollError(Exception error);
    void MarkAnalyticsRolloutNoticeSeen();
    bool ShouldShowAnalyticsRolloutNotice { get; }
    bool HandlePendingCrashReport(out bool showPrompt);
}

public interface IBackgroundService
{
    void MarkAppRunning();
    void MarkUserQuit();
    void Sync(bool launchAtLogin, bool runInBackground, bool relaunchOnCrash);
}

public interface IUpdaterService
{
    bool SupportsManualUpdates { get; }
    Task CheckForUpdatesAsync();
}
