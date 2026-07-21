using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Media.Imaging;
using Toast.Core.Store;
using Toast.Helpers;
using Toast.Services;
using Toast.Views;
using H.NotifyIcon;

namespace Toast;

public partial class App : Application
{
    private Window? _window;
    private TaskbarIcon? _tray;
    private DeploymentStore? _store;
    private WindowsNotificationService? _notifications;
    private WindowsBackgroundService? _background;
    private PostHogAnalyticsService? _analytics;
    private VelopackUpdaterService? _updater;
    private bool _isQuitting;
    private AggregateStatus? _lastTrayStatus;

    public static DeploymentStore Store { get; private set; } = null!;
    public static PostHogAnalyticsService Analytics { get; private set; } = null!;
    public static VelopackUpdaterService Updater { get; private set; } = null!;
    public static Window? MainWindowInstance { get; private set; }

    public App()
    {
        InitializeComponent();
        UnhandledException += OnUnhandledException;
        AppDomain.CurrentDomain.UnhandledException += OnDomainUnhandledException;
        TaskScheduler.UnobservedTaskException += OnUnobservedTaskException;
    }

    protected override void OnLaunched(LaunchActivatedEventArgs args)
    {
        AppConfig.Reload();

        var prefs = new JsonPreferencesStore();
        var tokens = new CredentialTokenStore();
        _notifications = new WindowsNotificationService();
        _analytics = new PostHogAnalyticsService(prefs, AppConfig.Current);
        _background = new WindowsBackgroundService(prefs);
        _updater = new VelopackUpdaterService(AppConfig.Current, prefs);

        if (_background.WasUnexpectedExit())
        {
            _analytics.MarkPendingCrashReport();
        }

        _store = new DeploymentStore(tokens, prefs, _notifications, _analytics, _background);
        Store = _store;
        Analytics = _analytics;
        Updater = _updater;

        _analytics.StartIfNeeded();
        _analytics.TrackAppLaunch();
        _store.Bootstrap();

        _window = new MainWindow();
        MainWindowInstance = _window;
        ConfigureWindow(_window);

        SetupTray();
        _updater.UpdateAvailable += OnUpdateAvailable;
        _notifications.NotificationRequested += OnNotificationRequested;

        if (_analytics.HandlePendingCrashReport(out var showCrash)
            && showCrash)
        {
            ShowWindow(navigate: w => w.ShowCrashPrompt());
        }
        else if (_store.HasCompletedOnboarding
                 && _analytics.ShouldShowAnalyticsRolloutNotice)
        {
            ShowWindow(navigate: w => w.ShowAnalyticsNotice());
        }
        else if (!_store.HasCompletedOnboarding)
        {
            ShowWindow(navigate: w => w.NavigateToOnboarding());
        }
        else
        {
            // Stay tray-only after onboarding — Mac menu-bar parity.
            HideToTray();
        }

        if (_store.HasCompletedOnboarding)
        {
            _updater.StartBackgroundChecks();
        }
    }

    public void QuitFromUser()
    {
        _isQuitting = true;
        _updater?.StopBackgroundChecks();
        _background?.MarkUserQuit();
        _store?.StopPolling();
        _tray?.Dispose();
        _tray = null;
        Exit();
    }

    public void StartUpdateChecksAfterOnboarding() =>
        _updater?.StartBackgroundChecks();

    private void OnUpdateAvailable(object? sender, UpdateAvailableEventArgs e)
    {
        _window?.DispatcherQueue.TryEnqueue(() =>
        {
            if (_analytics?.IsEnabled == true)
            {
                _analytics.Capture("update_available", new Dictionary<string, object>
                {
                    ["to_version"] = e.Version,
                    ["manual"] = e.FromManualCheck,
                });
            }

            ShowWindow(navigate: w => w.ShowUpdateAvailable(e.Version));
        });
    }

    private void ConfigureWindow(Window window)
    {
        var iconPath = Path.Combine(AppContext.BaseDirectory, "Assets", "Toast.ico");
        if (File.Exists(iconPath))
        {
            try
            {
                window.AppWindow.SetIcon(iconPath);
            }
            catch
            {
                // Icon is best-effort.
            }
        }

        window.AppWindow.Closing += (_, e) =>
        {
            if (_isQuitting || _store is null || !_store.RunInBackgroundEnabled)
            {
                _isQuitting = true;
                _background?.MarkUserQuit();
                _store?.StopPolling();
                _tray?.Dispose();
                _tray = null;
                return;
            }

            e.Cancel = true;
            HideToTray();
        };
    }

    private void SetupTray()
    {
        var flyout = new Microsoft.UI.Xaml.Controls.MenuFlyout();

        var open = new Microsoft.UI.Xaml.Controls.MenuFlyoutItem { Text = "Open Toast" };
        open.Click += (_, _) => OpenPopover();
        flyout.Items.Add(open);

        var settings = new Microsoft.UI.Xaml.Controls.MenuFlyoutItem { Text = "Settings" };
        settings.Click += (_, _) =>
        {
            ShowWindow(navigate: w => w.NavigateToSettings());
        };
        flyout.Items.Add(settings);

        flyout.Items.Add(new Microsoft.UI.Xaml.Controls.MenuFlyoutSeparator());

        var quit = new Microsoft.UI.Xaml.Controls.MenuFlyoutItem { Text = "Quit Toast" };
        quit.Click += (_, _) => QuitFromUser();
        flyout.Items.Add(quit);

        _tray = new TaskbarIcon
        {
            ToolTipText = "Toast",
            IconSource = CreateIconSource(TrayIconName(AggregateStatus.Idle)),
            ContextFlyout = flyout,
            NoLeftClickDelay = true,
        };
        try
        {
            // Required for code-created tray icons; keeps the process alive when the window is hidden.
            _tray.ForceCreate(enablesEfficiencyMode: true);
        }
        catch
        {
            // Older H.NotifyIcon builds create on first show; ignore.
        }
        _tray.LeftClickCommand = new RelayCommand(OpenPopover);

        _store!.StateChanged += (_, _) =>
        {
            _window?.DispatcherQueue.TryEnqueue(UpdateTray);
        };
        UpdateTray();
    }

    private void OpenPopover()
    {
        if (_store is null)
        {
            return;
        }

        if (!_store.HasCompletedOnboarding)
        {
            ShowWindow(navigate: w => w.NavigateToOnboarding());
            return;
        }

        if (_updater?.PendingVersion is { Length: > 0 } version)
        {
            ShowWindow(navigate: w => w.ShowUpdateAvailable(version));
            return;
        }

        ShowWindow(navigate: w => w.NavigateToPopover());
    }

    private void ShowWindow(Action<MainWindow>? navigate = null)
    {
        if (_window is null)
        {
            return;
        }

        _window.AppWindow.IsShownInSwitchers = true;
        if (_window is MainWindow main && navigate is not null)
        {
            navigate(main);
        }

        try
        {
            _window.Show(disableEfficiencyMode: true);
        }
        catch
        {
            try
            {
                _window.AppWindow.Show();
            }
            catch
            {
                // Some hosts throw if already visible.
            }
        }

        _window.Activate();
    }

    private void HideToTray()
    {
        if (_window is null)
        {
            return;
        }

        _window.AppWindow.IsShownInSwitchers = false;
        try
        {
            // Prefer H.NotifyIcon hide helper when available (pairs with ForceCreate efficiency mode).
            _window.Hide(enableEfficiencyMode: true);
        }
        catch
        {
            try
            {
                _window.AppWindow.Hide();
            }
            catch
            {
                // Ignore hide failures.
            }
        }
    }

    private void UpdateTray()
    {
        if (_tray is null || _store is null)
        {
            return;
        }

        var status = _store.AggregateStatus;
        var label = status switch
        {
            AggregateStatus.Building => "Toast — Building",
            AggregateStatus.Ready => "Toast — Ready",
            AggregateStatus.Error => "Toast — Error",
            AggregateStatus.Disconnected => "Toast — Disconnected",
            _ => "Toast",
        };

        if (_store.ShowStatusText && status == AggregateStatus.Building)
        {
            label = "Toast — BUILD";
        }
        else if (_store.ShowStatusText && status == AggregateStatus.Error)
        {
            label = "Toast — ERR";
        }

        _tray.ToolTipText = label;

        if (_lastTrayStatus != status)
        {
            _lastTrayStatus = status;
            try
            {
                _tray.IconSource = CreateIconSource(TrayIconName(status));
            }
            catch
            {
                // Keep previous icon if swap fails.
            }
        }
    }

    private static string TrayIconName(AggregateStatus status) => status switch
    {
        AggregateStatus.Ready => "Tray-Ready.ico",
        AggregateStatus.Building => "Tray-Building.ico",
        AggregateStatus.Error => "Tray-Error.ico",
        AggregateStatus.Disconnected => "Tray-Disconnected.ico",
        _ => "Tray-Idle.ico",
    };

    private static BitmapImage CreateIconSource(string fileName)
    {
        var path = Path.Combine(AppContext.BaseDirectory, "Assets", fileName);
        if (!File.Exists(path))
        {
            path = Path.Combine(AppContext.BaseDirectory, "Assets", "Toast.ico");
        }

        return new BitmapImage(new Uri(path));
    }

    private void OnNotificationRequested(object? sender, (string Title, string Body) e)
    {
        try
        {
            _tray?.ShowNotification(e.Title, e.Body);
        }
        catch
        {
            // Ignore notification failures.
        }
    }

    private void OnUnhandledException(object sender, Microsoft.UI.Xaml.UnhandledExceptionEventArgs e)
    {
        CaptureCrash(e.Exception, "ui_unhandled");
        // Keep Handled=false for fatal errors so the process exits cleanly and
        // the watchdog can relaunch; still record the exception first.
        e.Handled = false;
    }

    private void OnDomainUnhandledException(object sender, System.UnhandledExceptionEventArgs e)
    {
        if (e.ExceptionObject is Exception ex)
        {
            CaptureCrash(ex, "domain_unhandled");
        }
    }

    private void OnUnobservedTaskException(object? sender, UnobservedTaskExceptionEventArgs e)
    {
        CaptureCrash(e.Exception, "unobserved_task");
        e.SetObserved();
    }

    private void CaptureCrash(Exception? exception, string source)
    {
        try
        {
            _analytics?.CaptureCrash(exception, source);
        }
        catch
        {
            // Never throw from crash handlers.
        }
    }
}

internal sealed class RelayCommand : System.Windows.Input.ICommand
{
    private readonly Action _action;
    public RelayCommand(Action action) => _action = action;
#pragma warning disable CS0067
    public event EventHandler? CanExecuteChanged;
#pragma warning restore CS0067
    public bool CanExecute(object? parameter) => true;
    public void Execute(object? parameter) => _action();
}
