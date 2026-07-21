using Microsoft.UI.Xaml;
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

    public static DeploymentStore Store { get; private set; } = null!;
    public static PostHogAnalyticsService Analytics { get; private set; } = null!;
    public static VelopackUpdaterService Updater { get; private set; } = null!;
    public static Window? MainWindowInstance { get; private set; }

    public App()
    {
        InitializeComponent();
        UnhandledException += (_, e) =>
        {
            e.Handled = true;
        };
    }

    protected override void OnLaunched(LaunchActivatedEventArgs args)
    {
        AppConfig.Reload();

        var prefs = new JsonPreferencesStore();
        var tokens = new CredentialTokenStore();
        _notifications = new WindowsNotificationService();
        _analytics = new PostHogAnalyticsService(prefs, AppConfig.Current);
        _background = new WindowsBackgroundService(prefs);
        _updater = new VelopackUpdaterService(AppConfig.Current);

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
        _window.Closed += (_, _) =>
        {
            _background.MarkUserQuit();
            _store.StopPolling();
            _tray?.Dispose();
        };

        _window.AppWindow.IsShownInSwitchers = false;

        SetupTray();
        _notifications.NotificationRequested += OnNotificationRequested;

        if (_analytics.HandlePendingCrashReport(out var showCrash)
            && showCrash)
        {
            _window.Activate();
            (_window as MainWindow)?.ShowCrashPrompt();
        }
        else if (_store.HasCompletedOnboarding
                 && _analytics.ShouldShowAnalyticsRolloutNotice)
        {
            _window.Activate();
            (_window as MainWindow)?.ShowAnalyticsNotice();
        }
        else if (!_store.HasCompletedOnboarding)
        {
            _window.Activate();
            (_window as MainWindow)?.NavigateToOnboarding();
        }
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
            _window?.Activate();
            (_window as MainWindow)?.NavigateToSettings();
        };
        flyout.Items.Add(settings);

        flyout.Items.Add(new Microsoft.UI.Xaml.Controls.MenuFlyoutSeparator());

        var quit = new Microsoft.UI.Xaml.Controls.MenuFlyoutItem { Text = "Quit Toast" };
        quit.Click += (_, _) =>
        {
            _background?.MarkUserQuit();
            _store?.StopPolling();
            _tray?.Dispose();
            Exit();
        };
        flyout.Items.Add(quit);

        _tray = new TaskbarIcon
        {
            ToolTipText = "Toast",
            IconSource = CreateIconSource(),
            ContextFlyout = flyout,
            NoLeftClickDelay = true,
        };
        _tray.LeftClickCommand = new RelayCommand(OpenPopover);

        _store!.StateChanged += (_, _) => UpdateTray();
        UpdateTray();
    }

    private void OpenPopover()
    {
        _window?.Activate();
        if (_store is null)
        {
            return;
        }

        if (!_store.HasCompletedOnboarding)
        {
            (_window as MainWindow)?.NavigateToOnboarding();
        }
        else
        {
            (_window as MainWindow)?.NavigateToPopover();
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
    }

    private static Microsoft.UI.Xaml.Media.Imaging.BitmapImage CreateIconSource()
    {
        var path = Path.Combine(AppContext.BaseDirectory, "Assets", "Toast.ico");
        return new Microsoft.UI.Xaml.Media.Imaging.BitmapImage(new Uri(path));
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
