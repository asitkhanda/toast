using System.ComponentModel;
using System.Runtime.CompilerServices;
using Toast.Core.Models;
using Toast.Core.Services;

namespace Toast.Core.Store;

public enum AggregateStatus
{
    Idle,
    Building,
    Ready,
    Error,
    Disconnected,
}

public sealed class BackgroundPreferences
{
    public bool LaunchAtLogin { get; set; } = true;
    public bool RunInBackground { get; set; } = true;
    public bool RelaunchOnCrash { get; set; } = true;

    public static BackgroundPreferences Defaults { get; } = new();
}

public sealed class ProjectDeploymentStatus
{
    public required WatchedProject Watched { get; init; }
    public Deployment? Deployment { get; init; }
    public DateTimeOffset FetchedAt { get; init; }
    public string Id => Watched.Id;
    public DeploymentState Status => Deployment?.Status ?? DeploymentState.Queued;
}

public sealed class DeploymentStore : INotifyPropertyChanged
{
    private static class Keys
    {
        public const string OnboardingComplete = "onboardingComplete";
        public const string ShowStatusText = "showStatusText";
        public const string NotificationsEnabled = "notificationsEnabled";
        public const string LaunchAtLogin = "launchAtLogin";
        public const string RunInBackground = "runInBackground";
        public const string RelaunchOnCrash = "relaunchOnCrash";
        public const string BackgroundBehaviorConfigured = "backgroundBehaviorConfigured";
        public const string SelectedTeamId = "selectedTeamId";
        public const string WatchedProjects = "watchedProjects";
    }

    private readonly ITokenStore _tokens;
    private readonly IPreferencesStore _prefs;
    private readonly INotificationService _notifications;
    private readonly IAnalyticsService _analytics;
    private readonly IBackgroundService _background;

    private bool _hasCompletedOnboarding;
    private bool _showStatusText = true;
    private bool _notificationsEnabled = true;
    private bool _launchAtLoginEnabled = true;
    private bool _runInBackgroundEnabled = true;
    private bool _relaunchOnCrashEnabled = true;
    private string? _selectedTeamId;
    private List<WatchedProject> _watchedProjects = [];
    private List<Team> _teams = [];
    private List<Project> _projects = [];
    private List<ProjectDeploymentStatus> _projectStatuses = [];
    private bool _isLoading;
    private bool _isFinishingOnboarding;
    private string? _lastError;
    private string? _tokenScopeWarning;
    private DateTimeOffset? _lastRefresh;
    private bool _isConnected;
    private string? _connectedTeamName;
    private CancellationTokenSource? _pollCts;
    private readonly Dictionary<string, DeploymentState> _previousStatuses = new();
    private bool _isLoadingPreferences;

    public DeploymentStore(
        ITokenStore tokens,
        IPreferencesStore prefs,
        INotificationService notifications,
        IAnalyticsService analytics,
        IBackgroundService background)
    {
        _tokens = tokens;
        _prefs = prefs;
        _notifications = notifications;
        _analytics = analytics;
        _background = background;
        LoadPreferences();
    }

    public event PropertyChangedEventHandler? PropertyChanged;
    public event EventHandler? StateChanged;

    public bool HasCompletedOnboarding
    {
        get => _hasCompletedOnboarding;
        private set => SetField(ref _hasCompletedOnboarding, value);
    }

    public bool ShowStatusText
    {
        get => _showStatusText;
        set
        {
            var old = _showStatusText;
            if (!SetField(ref _showStatusText, value))
            {
                return;
            }

            _prefs.SetBool(Keys.ShowStatusText, value);
            TrackSettingChanged("show_status_text", value, old);
        }
    }

    public bool NotificationsEnabled
    {
        get => _notificationsEnabled;
        set
        {
            var old = _notificationsEnabled;
            if (!SetField(ref _notificationsEnabled, value))
            {
                return;
            }

            _prefs.SetBool(Keys.NotificationsEnabled, value);
            TrackSettingChanged("notifications_enabled", value, old);
        }
    }

    public bool LaunchAtLoginEnabled
    {
        get => _launchAtLoginEnabled;
        set
        {
            var old = _launchAtLoginEnabled;
            if (!SetField(ref _launchAtLoginEnabled, value))
            {
                return;
            }

            PersistBackgroundPreferenceChange();
            TrackSettingChanged("launch_at_login", value, old);
        }
    }

    public bool RunInBackgroundEnabled
    {
        get => _runInBackgroundEnabled;
        set
        {
            var old = _runInBackgroundEnabled;
            if (!SetField(ref _runInBackgroundEnabled, value))
            {
                return;
            }

            PersistBackgroundPreferenceChange();
            TrackSettingChanged("run_in_background", value, old);
        }
    }

    public bool RelaunchOnCrashEnabled
    {
        get => _relaunchOnCrashEnabled;
        set
        {
            var old = _relaunchOnCrashEnabled;
            if (!SetField(ref _relaunchOnCrashEnabled, value))
            {
                return;
            }

            PersistBackgroundPreferenceChange();
            TrackSettingChanged("relaunch_on_crash", value, old);
        }
    }

    public string? SelectedTeamId
    {
        get => _selectedTeamId;
        set
        {
            if (!SetField(ref _selectedTeamId, value))
            {
                return;
            }

            PersistSelectedTeamId();
        }
    }

    public IReadOnlyList<WatchedProject> WatchedProjects => _watchedProjects;
    public IReadOnlyList<Team> Teams => _teams;
    public IReadOnlyList<Project> Projects => _projects;
    public IReadOnlyList<ProjectDeploymentStatus> ProjectStatuses => _projectStatuses;
    public bool IsLoading => _isLoading;
    public bool IsFinishingOnboarding => _isFinishingOnboarding;
    public string? LastError => _lastError;
    public string? TokenScopeWarning => _tokenScopeWarning;
    public DateTimeOffset? LastRefresh => _lastRefresh;
    public bool IsConnected => _isConnected;
    public string? ConnectedTeamName => _connectedTeamName;

    public AggregateStatus AggregateStatus
    {
        get
        {
            if (!_isConnected && _hasCompletedOnboarding)
            {
                return AggregateStatus.Disconnected;
            }

            var statuses = _projectStatuses.Select(s => s.Status).ToList();
            if (statuses.Any(s => s is DeploymentState.Error or DeploymentState.Canceled or DeploymentState.Blocked))
            {
                return AggregateStatus.Error;
            }

            if (statuses.Any(s => s.IsInProgress()))
            {
                return AggregateStatus.Building;
            }

            if (statuses.Any(s => s == DeploymentState.Ready))
            {
                return AggregateStatus.Ready;
            }

            return AggregateStatus.Idle;
        }
    }

    public void Bootstrap()
    {
        _background.MarkAppRunning();
        ApplyDefaultBackgroundBehaviorIfNeeded();
        SyncBackgroundBehavior();
        _isConnected = _tokens.HasToken();
        Notify(nameof(IsConnected));

        if (_hasCompletedOnboarding && _tokens.HasToken())
        {
            _ = Task.Run(async () =>
            {
                await RestoreSessionIfNeededAsync();
                StartPolling();
            });
        }
        else if (_tokens.HasToken() && !_hasCompletedOnboarding)
        {
            _ = Task.Run(RestoreSessionAfterTokenSavedAsync);
        }
    }

    public async Task RestoreSessionIfNeededAsync(CancellationToken ct = default)
    {
        if (!_tokens.HasToken())
        {
            return;
        }

        if (_teams.Count > 0 && _projects.Count > 0)
        {
            UpdateConnectedTeamName();
            SetConnected(true);
            return;
        }

        var client = MakeApiClient();
        if (client is null)
        {
            return;
        }

        try
        {
            _teams = (await client.ListTeamsAsync(ct)).ToList();
            Notify(nameof(Teams));
            if (_selectedTeamId is null)
            {
                SelectedTeamId = _teams.FirstOrDefault()?.Id;
            }

            UpdateConnectedTeamName();
            if (_selectedTeamId is not null)
            {
                _projects = (await client.ListProjectsAsync(_selectedTeamId, ct)).ToList();
                Notify(nameof(Projects));
            }

            SetConnected(true);
            SetLastError(null);
        }
        catch (Exception ex)
        {
            SetLastError(ex.Message);
            if (ex is VercelApiException { Kind: VercelApiErrorKind.Unauthorized })
            {
                SetConnected(false);
            }
        }
    }

    public async Task ConnectAsync(string token, CancellationToken ct = default)
    {
        var trimmed = token.Trim();
        if (string.IsNullOrEmpty(trimmed))
        {
            return;
        }

        SetLoading(true);
        try
        {
            var client = new VercelApiClient(trimmed);
            var validation = await client.ValidateTokenAsync(ct);
            _tokens.SaveToken(trimmed);
            SetConnected(true);
            _tokenScopeWarning = validation.ScopeWarning;
            Notify(nameof(TokenScopeWarning));
            SetLastError(null);

            _teams = (await client.ListTeamsAsync(ct)).ToList();
            Notify(nameof(Teams));
            if (_selectedTeamId is null)
            {
                SelectedTeamId = _teams.FirstOrDefault()?.Id;
            }

            UpdateConnectedTeamName();
            if (_selectedTeamId is not null)
            {
                _projects = (await client.ListProjectsAsync(_selectedTeamId, ct)).ToList();
                Notify(nameof(Projects));
            }

            _analytics.Capture("token_connected");
        }
        finally
        {
            SetLoading(false);
        }
    }

    public void Disconnect()
    {
        StopPolling();
        _tokens.DeleteToken();
        SetConnected(false);
        _connectedTeamName = null;
        Notify(nameof(ConnectedTeamName));
        HasCompletedOnboarding = false;
        _prefs.SetBool(Keys.OnboardingComplete, false);
        _teams = [];
        _projects = [];
        _projectStatuses = [];
        _watchedProjects = [];
        SelectedTeamId = null;
        SetLastError(null);
        _tokenScopeWarning = null;
        Notify(nameof(TokenScopeWarning));
        Notify(nameof(Teams));
        Notify(nameof(Projects));
        Notify(nameof(ProjectStatuses));
        Notify(nameof(WatchedProjects));
        PersistAllPreferences();
    }

    public async Task CompleteOnboardingAsync(
        IReadOnlyList<WatchedProject> selected,
        BackgroundPreferences? preferences = null,
        CancellationToken ct = default)
    {
        if (selected.Count == 0)
        {
            return;
        }

        _isFinishingOnboarding = true;
        Notify(nameof(IsFinishingOnboarding));
        SetLastError(null);
        try
        {
            _watchedProjects = selected.ToList();
            Notify(nameof(WatchedProjects));
            HasCompletedOnboarding = true;
            _prefs.SetBool(Keys.OnboardingComplete, true);
            ConfigureBackgroundBehavior(preferences ?? BackgroundPreferences.Defaults);
            PersistAllPreferences();
            _analytics.MarkAnalyticsRolloutNoticeSeen();

            StartPolling();
            await RefreshNowAsync(ct);
            _analytics.Capture("onboarding_completed", new Dictionary<string, object>
            {
                ["projects_watched_bucket"] = Diagnostics.ProjectsWatchedBucket(selected.Count),
            });
        }
        finally
        {
            _isFinishingOnboarding = false;
            Notify(nameof(IsFinishingOnboarding));
        }
    }

    public void ConfigureBackgroundBehavior(BackgroundPreferences preferences)
    {
        _isLoadingPreferences = true;
        LaunchAtLoginEnabled = preferences.LaunchAtLogin;
        RunInBackgroundEnabled = preferences.RunInBackground;
        RelaunchOnCrashEnabled = preferences.RelaunchOnCrash;
        _isLoadingPreferences = false;

        _prefs.SetBool(Keys.BackgroundBehaviorConfigured, true);
        SyncBackgroundBehavior();
    }

    public async Task ReloadProjectsAsync(CancellationToken ct = default)
    {
        if (!_tokens.HasToken() || _selectedTeamId is null)
        {
            return;
        }

        SetLoading(true);
        try
        {
            var client = MakeApiClient();
            if (client is null)
            {
                return;
            }

            _projects = (await client.ListProjectsAsync(_selectedTeamId, ct)).ToList();
            Notify(nameof(Projects));
            SetLastError(null);
        }
        catch (Exception ex)
        {
            SetLastError(ex.Message);
        }
        finally
        {
            SetLoading(false);
        }
    }

    public void UpdateWatchedProjects(IReadOnlyList<WatchedProject> selected)
    {
        _watchedProjects = selected.ToList();
        Notify(nameof(WatchedProjects));
        PersistWatchedProjects();
        StartPolling();
        _ = RefreshNowAsync();
    }

    public Task RefreshNowAsync(CancellationToken ct = default) => RefreshAsync(0, ct);

    public void StartPolling()
    {
        StopPolling();
        _pollCts = new CancellationTokenSource();
        var token = _pollCts.Token;
        _ = Task.Run(async () =>
        {
            while (!token.IsCancellationRequested)
            {
                await RefreshAsync(0, token);
                var interval = PollIntervalSeconds();
                try
                {
                    await Task.Delay(TimeSpan.FromSeconds(interval), token);
                }
                catch (OperationCanceledException)
                {
                    break;
                }
            }
        }, token);
    }

    public void StopPolling()
    {
        _pollCts?.Cancel();
        _pollCts?.Dispose();
        _pollCts = null;
    }

    private async Task RestoreSessionAfterTokenSavedAsync()
    {
        var token = _tokens.LoadToken();
        if (token is null)
        {
            return;
        }

        try
        {
            await ConnectAsync(token);
        }
        catch (Exception ex)
        {
            SetLastError(ex.Message);
            SetConnected(false);
        }
    }

    private double PollIntervalSeconds() =>
        _projectStatuses.Any(s => s.Status.IsInProgress()) ? 5 : 60;

    private async Task RefreshAsync(double minIntervalSinceLastSuccess, CancellationToken ct)
    {
        if (!_tokens.HasToken())
        {
            return;
        }

        var client = MakeApiClient();
        if (client is null)
        {
            return;
        }

        if (_watchedProjects.Count == 0)
        {
            _projectStatuses = [];
            Notify(nameof(ProjectStatuses));
            Notify(nameof(AggregateStatus));
            return;
        }

        if (minIntervalSinceLastSuccess > 0
            && _lastRefresh is not null
            && (DateTimeOffset.UtcNow - _lastRefresh.Value).TotalSeconds < minIntervalSinceLastSuccess)
        {
            return;
        }

        SetLoading(true);
        try
        {
            var results = new List<ProjectDeploymentStatus>();
            string? fetchError = null;
            Exception? pollError = null;

            foreach (var watched in _watchedProjects)
            {
                try
                {
                    var deployments = await client.ListDeploymentsAsync(
                        watched.ProjectId,
                        watched.TeamId,
                        limit: 1,
                        ct);
                    var deployment = deployments.FirstOrDefault();
                    results.Add(new ProjectDeploymentStatus
                    {
                        Watched = watched,
                        Deployment = deployment,
                        FetchedAt = DateTimeOffset.UtcNow,
                    });
                    await HandleStatusTransitionAsync(watched, deployment);
                }
                catch (Exception ex)
                {
                    fetchError = ex.Message;
                    pollError = ex;
                    if (ex is VercelApiException { Kind: VercelApiErrorKind.Unauthorized })
                    {
                        SetConnected(false);
                    }

                    results.Add(new ProjectDeploymentStatus
                    {
                        Watched = watched,
                        Deployment = null,
                        FetchedAt = DateTimeOffset.UtcNow,
                    });
                }
            }

            _projectStatuses = results;
            _lastRefresh = DateTimeOffset.UtcNow;
            Notify(nameof(ProjectStatuses));
            Notify(nameof(LastRefresh));
            Notify(nameof(AggregateStatus));
            SetLastError(fetchError);
            if (pollError is not null)
            {
                _analytics.CapturePollError(pollError);
            }
            else if (fetchError is null)
            {
                SetConnected(true);
            }
        }
        finally
        {
            SetLoading(false);
        }
    }

    private async Task HandleStatusTransitionAsync(WatchedProject watched, Deployment? deployment)
    {
        if (!_notificationsEnabled || deployment is null)
        {
            return;
        }

        var key = watched.Id;
        var newStatus = deployment.Status;
        if (!_previousStatuses.TryGetValue(key, out var oldStatus))
        {
            _previousStatuses[key] = newStatus;
            return;
        }

        _previousStatuses[key] = newStatus;
        if (!oldStatus.IsInProgress() || !newStatus.IsTerminal())
        {
            return;
        }

        string title;
        string body;
        switch (newStatus)
        {
            case DeploymentState.Ready:
                title = $"{watched.ProjectName} deployed";
                body = deployment.CommitMessage ?? "Deployment is ready.";
                break;
            case DeploymentState.Error:
                title = $"{watched.ProjectName} failed";
                body = deployment.CommitMessage ?? "Deployment failed.";
                break;
            default:
                return;
        }

        await _notifications.NotifyAsync(title, body);
    }

    private VercelApiClient? MakeApiClient()
    {
        var token = _tokens.LoadToken();
        return token is null ? null : new VercelApiClient(token);
    }

    private void LoadPreferences()
    {
        _isLoadingPreferences = true;
        try
        {
            _hasCompletedOnboarding = _prefs.GetBool(Keys.OnboardingComplete, false);
            _showStatusText = _prefs.GetBool(Keys.ShowStatusText, true);
            _notificationsEnabled = _prefs.GetBool(Keys.NotificationsEnabled, true);
            _launchAtLoginEnabled = _prefs.GetBool(Keys.LaunchAtLogin, true);
            _runInBackgroundEnabled = _prefs.GetBool(Keys.RunInBackground, true);
            _relaunchOnCrashEnabled = _prefs.GetBool(Keys.RelaunchOnCrash, true);
            _selectedTeamId = _prefs.GetString(Keys.SelectedTeamId);
            _watchedProjects = _prefs.GetJson<List<WatchedProject>>(Keys.WatchedProjects) ?? [];
        }
        finally
        {
            _isLoadingPreferences = false;
        }
    }

    private void PersistAllPreferences()
    {
        _prefs.SetBool(Keys.OnboardingComplete, _hasCompletedOnboarding);
        PersistWatchedProjects();
        PersistSelectedTeamId();
    }

    private void PersistWatchedProjects() =>
        _prefs.SetJson(Keys.WatchedProjects, _watchedProjects);

    private void PersistSelectedTeamId()
    {
        _prefs.SetString(Keys.SelectedTeamId, _selectedTeamId);
        UpdateConnectedTeamName();
    }

    private void UpdateConnectedTeamName()
    {
        _connectedTeamName = _teams.FirstOrDefault(t => t.Id == _selectedTeamId)?.DisplayName;
        Notify(nameof(ConnectedTeamName));
    }

    private void ApplyDefaultBackgroundBehaviorIfNeeded()
    {
        if (!_hasCompletedOnboarding)
        {
            return;
        }

        if (_prefs.GetBool(Keys.BackgroundBehaviorConfigured, false))
        {
            return;
        }

        ConfigureBackgroundBehavior(new BackgroundPreferences
        {
            LaunchAtLogin = _prefs.GetBool(Keys.LaunchAtLogin, true),
            RunInBackground = _prefs.GetBool(Keys.RunInBackground, true),
            RelaunchOnCrash = _prefs.GetBool(Keys.RelaunchOnCrash, true),
        });
    }

    private void SyncBackgroundBehavior() =>
        _background.Sync(_launchAtLoginEnabled, _runInBackgroundEnabled, _relaunchOnCrashEnabled);

    private void PersistBackgroundPreferenceChange()
    {
        if (_isLoadingPreferences)
        {
            return;
        }

        _prefs.SetBool(Keys.LaunchAtLogin, _launchAtLoginEnabled);
        _prefs.SetBool(Keys.RunInBackground, _runInBackgroundEnabled);
        _prefs.SetBool(Keys.RelaunchOnCrash, _relaunchOnCrashEnabled);
        _prefs.SetBool(Keys.BackgroundBehaviorConfigured, true);
        SyncBackgroundBehavior();
    }

    private void TrackSettingChanged(string setting, bool value, bool oldValue)
    {
        if (_isLoadingPreferences || value == oldValue)
        {
            return;
        }

        _analytics.CaptureSettingChanged(setting, value);
    }

    private void SetLoading(bool value)
    {
        if (SetField(ref _isLoading, value))
        {
            Notify(nameof(IsLoading));
        }
    }

    private void SetConnected(bool value)
    {
        if (SetField(ref _isConnected, value))
        {
            Notify(nameof(IsConnected));
            Notify(nameof(AggregateStatus));
        }
    }

    private void SetLastError(string? value)
    {
        if (SetField(ref _lastError, value))
        {
            Notify(nameof(LastError));
        }
    }

    private bool SetField<T>(ref T field, T value, [CallerMemberName] string? name = null)
    {
        if (EqualityComparer<T>.Default.Equals(field, value))
        {
            return false;
        }

        field = value;
        if (name is not null)
        {
            Notify(name);
        }

        StateChanged?.Invoke(this, EventArgs.Empty);
        return true;
    }

    private void Notify(string name)
    {
        PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(name));
        if (name is nameof(ProjectStatuses) or nameof(IsConnected) or nameof(HasCompletedOnboarding))
        {
            StateChanged?.Invoke(this, EventArgs.Empty);
        }
    }
}
