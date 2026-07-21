using System.Net.Http.Headers;
using System.Text;
using System.Text.Json;
using Toast.Core;
using Toast.Core.Services;
using Toast.Helpers;

namespace Toast.Services;

public sealed class PostHogAnalyticsService : IAnalyticsService
{
    private const string EnabledKey = "analyticsEnabled";
    private const string HasReportedFirstLaunchKey = "hasReportedFirstLaunch";
    private const string LastAppOpenedDayKey = "lastAppOpenedDay";
    private const string LastPollErrorTimestampKey = "lastPollErrorTimestamp";
    private const string LastTrackedVersionKey = "lastTrackedAppVersion";
    private const string HasSeenAnalyticsRolloutNoticeKey = "hasSeenAnalyticsRolloutNotice";
    private const string PendingCrashReportKey = "pendingCrashReport";
    private const string CrashPromptSuppressedKey = "crashPromptSuppressed";

    private readonly IPreferencesStore _prefs;
    private readonly HttpClient _http = new();
    private readonly string? _apiKey;
    private readonly string _host;
    private bool _isStarted;
    private string? _distinctId;

    public PostHogAnalyticsService(IPreferencesStore prefs, AppConfig config)
    {
        _prefs = prefs;
        _apiKey = string.IsNullOrWhiteSpace(config.PostHogApiKey) ? null : config.PostHogApiKey.Trim();
        _host = string.IsNullOrWhiteSpace(config.PostHogHost) ? "https://us.i.posthog.com" : config.PostHogHost.TrimEnd('/');
    }

    public bool IsEnabled
    {
        get => _prefs.GetBool(EnabledKey, true);
        set
        {
            _prefs.SetBool(EnabledKey, value);
            if (value)
            {
                StartIfNeeded();
            }
            else
            {
                Stop();
            }
        }
    }

    public bool ShouldShowAnalyticsRolloutNotice =>
        IsEnabled && !_prefs.GetBool(HasSeenAnalyticsRolloutNoticeKey, false);

    public void MarkAnalyticsRolloutNoticeSeen() =>
        _prefs.SetBool(HasSeenAnalyticsRolloutNoticeKey, true);

    public void StartIfNeeded()
    {
        if (!IsEnabled || _apiKey is null)
        {
            return;
        }

        _isStarted = true;
        _distinctId ??= EnsureDistinctId();
    }

    public void Stop() => _isStarted = false;

    public void TrackAppLaunch()
    {
        StartIfNeeded();
        if (!_isStarted)
        {
            return;
        }

        var version = AppConfig.Current.AppVersion;
        var last = _prefs.GetString(LastTrackedVersionKey);
        if (last != version)
        {
            Capture("app_updated", new Dictionary<string, object>
            {
                ["from_version"] = last ?? "none",
                ["to_version"] = version,
            });
            _prefs.SetString(LastTrackedVersionKey, version);
        }

        if (!_prefs.GetBool(HasReportedFirstLaunchKey, false))
        {
            Capture("first_launch");
            _prefs.SetBool(HasReportedFirstLaunchKey, true);
        }

        var today = DateTime.UtcNow.ToString("yyyy-MM-dd");
        if (_prefs.GetString(LastAppOpenedDayKey) != today)
        {
            Capture("app_opened");
            _prefs.SetString(LastAppOpenedDayKey, today);
        }
    }

    public bool HandlePendingCrashReport(out bool showPrompt)
    {
        showPrompt = false;
        if (!_prefs.GetBool(PendingCrashReportKey, false))
        {
            return false;
        }

        _prefs.SetBool(PendingCrashReportKey, false);
        Capture("launcher_relaunch", Diagnostics.Snapshot(
            onboardingCompleted: true,
            projectsWatched: 0,
            launchAtLogin: true,
            runInBackground: true,
            relaunchOnCrash: true,
            notificationsEnabled: true,
            showStatusText: true,
            analyticsEnabled: IsEnabled,
            appVersion: AppConfig.Current.AppVersion,
            build: AppConfig.Current.AppBuild,
            launcherRelaunch: true));

        if (!IsEnabled || _prefs.GetBool(CrashPromptSuppressedKey, false))
        {
            return false;
        }

        showPrompt = true;
        return true;
    }

    public void MarkPendingCrashReport() => _prefs.SetBool(PendingCrashReportKey, true);

    public void SuppressCrashPrompt(bool suppress) =>
        _prefs.SetBool(CrashPromptSuppressedKey, suppress);

    public void Capture(string eventName, IReadOnlyDictionary<string, object>? properties = null)
    {
        if (!_isStarted || _apiKey is null)
        {
            return;
        }

        _ = SendAsync(eventName, properties);
    }

    public void CaptureSettingChanged(string setting, bool value) =>
        Capture("setting_changed", new Dictionary<string, object>
        {
            ["setting"] = setting,
            ["value"] = value,
        });

    public void CapturePollError(Exception error)
    {
        if (!_isStarted)
        {
            return;
        }

        var last = _prefs.GetString(LastPollErrorTimestampKey);
        if (last is not null
            && DateTimeOffset.TryParse(last, out var lastTime)
            && DateTimeOffset.UtcNow - lastTime < TimeSpan.FromHours(1))
        {
            return;
        }

        _prefs.SetString(LastPollErrorTimestampKey, DateTimeOffset.UtcNow.ToString("O"));
        var props = new Dictionary<string, object>
        {
            ["error_type"] = error.GetType().Name,
        };
        if (error is Toast.Core.Services.VercelApiException vercel && vercel.StatusCode is int code)
        {
            props["status_code"] = code;
        }

        Capture("poll_error", props);
    }

    private async Task SendAsync(string eventName, IReadOnlyDictionary<string, object>? properties)
    {
        try
        {
            var payload = new Dictionary<string, object?>
            {
                ["api_key"] = _apiKey,
                ["event"] = eventName,
                ["distinct_id"] = _distinctId ?? "anonymous",
                ["properties"] = properties is null
                    ? new Dictionary<string, object> { ["$lib"] = "toast-win" }
                    : new Dictionary<string, object>(properties) { ["$lib"] = "toast-win" },
            };

            var json = JsonSerializer.Serialize(payload);
            using var content = new StringContent(json, Encoding.UTF8, "application/json");
            using var request = new HttpRequestMessage(HttpMethod.Post, $"{_host}/capture/");
            request.Content = content;
            request.Headers.Accept.Add(new MediaTypeWithQualityHeaderValue("application/json"));
            await _http.SendAsync(request);
        }
        catch
        {
            // Analytics must never break the app.
        }
    }

    private string EnsureDistinctId()
    {
        const string key = "analyticsDistinctId";
        var existing = _prefs.GetString(key);
        if (!string.IsNullOrWhiteSpace(existing))
        {
            return existing;
        }

        var id = Guid.NewGuid().ToString("N");
        _prefs.SetString(key, id);
        return id;
    }
}
