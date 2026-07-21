using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;
using Toast.Core.Store;
using Toast.Helpers;
using Windows.UI;

namespace Toast.Views;

public sealed partial class PopoverPage : Page
{
    public PopoverPage()
    {
        InitializeComponent();
        Loaded += async (_, _) =>
        {
            UpdateButton.Visibility = App.Updater.SupportsManualUpdates
                ? Visibility.Visible
                : Visibility.Collapsed;
            App.Store.StateChanged += OnStateChanged;
            Bind();
            await App.Store.RefreshNowAsync();
        };
        Unloaded += (_, _) => App.Store.StateChanged -= OnStateChanged;
    }

    private void OnStateChanged(object? sender, EventArgs e) =>
        DispatcherQueue.TryEnqueue(Bind);

    private void Bind()
    {
        var store = App.Store;
        HeaderTitle.Text = HeaderTitleFor(store);
        HeaderSubtitle.Text = store.LastError
            ?? SubtitleFor(store);

        BindStatusIcon(store);

        if (store.LastError is { Length: > 0 } error)
        {
            ErrorBanner.Text = error;
            ErrorBanner.Visibility = Visibility.Visible;
        }
        else
        {
            ErrorBanner.Visibility = Visibility.Collapsed;
        }

        StatusList.Children.Clear();

        if (store.WatchedProjects.Count == 0)
        {
            StatusList.Children.Add(EmptyState(
                "No projects watched",
                "Choose projects…",
                Settings_Click));
            return;
        }

        if (store.ProjectStatuses.Count == 0)
        {
            var loading = new StackPanel
            {
                Spacing = 8,
                HorizontalAlignment = HorizontalAlignment.Center,
                Margin = new Thickness(0, 24, 0, 24),
            };
            loading.Children.Add(new ProgressRing { Width = 28, Height = 28, IsActive = true });
            loading.Children.Add(new TextBlock
            {
                Text = "Loading deployments…",
                FontSize = 12,
                Foreground = (Brush)Application.Current.Resources["TextFillColorSecondaryBrush"],
                HorizontalAlignment = HorizontalAlignment.Center,
            });
            StatusList.Children.Add(loading);
            return;
        }

        var showNames = store.ProjectStatuses.Count > 1;
        foreach (var status in store.ProjectStatuses)
        {
            var row = new DeploymentRowControl();
            row.Bind(status, showProjectName: showNames);
            StatusList.Children.Add(row);
        }
    }

    private static string HeaderTitleFor(DeploymentStore store)
    {
        var count = store.WatchedProjects.Count;
        if (count == 1)
        {
            return store.WatchedProjects[0].ProjectName;
        }

        if (count > 1)
        {
            return $"{count} projects";
        }

        return store.ConnectedTeamName is { Length: > 0 } name ? name : "Toast";
    }

    private static string SubtitleFor(DeploymentStore store)
    {
        if (!store.IsConnected)
        {
            return "Disconnected — reconnect in Settings";
        }

        if (store.IsLoading && store.ProjectStatuses.Count == 0)
        {
            return "Fetching deployments…";
        }

        if (store.ProjectStatuses.Count == 1)
        {
            var status = store.ProjectStatuses[0];
            var deployed = RelativeDateFormat.FromUnixMs(
                status.Deployment?.Ready ?? status.Deployment?.CreatedAt);
            if (deployed is not null)
            {
                return $"{RelativeDateFormat.Label(deployed.Value, "Deployed")} · {RelativeDateFormat.Label(status.FetchedAt, "Checked")}";
            }

            return RelativeDateFormat.Label(status.FetchedAt, "Checked");
        }

        if (store.LastRefresh is { } last)
        {
            return RelativeDateFormat.Label(last, "Checked");
        }

        return "Live deployment status";
    }

    private void BindStatusIcon(DeploymentStore store)
    {
        if (store.IsLoading)
        {
            StatusIcon.Visibility = Visibility.Collapsed;
            LoadingRing.Visibility = Visibility.Visible;
            LoadingRing.IsActive = true;
            return;
        }

        LoadingRing.IsActive = false;
        LoadingRing.Visibility = Visibility.Collapsed;

        switch (store.AggregateStatus)
        {
            case AggregateStatus.Ready:
                StatusIcon.Glyph = "\uE73E"; // CheckMark
                StatusIcon.Foreground = new SolidColorBrush(Color.FromArgb(0xFF, 0x34, 0xC7, 0x59));
                StatusIcon.Visibility = Visibility.Visible;
                break;
            case AggregateStatus.Building:
                StatusIcon.Visibility = Visibility.Collapsed;
                LoadingRing.Visibility = Visibility.Visible;
                LoadingRing.IsActive = true;
                break;
            case AggregateStatus.Error:
                StatusIcon.Glyph = "\uE711"; // Cancel
                StatusIcon.Foreground = new SolidColorBrush(Color.FromArgb(0xFF, 0xFF, 0x3B, 0x30));
                StatusIcon.Visibility = Visibility.Visible;
                break;
            case AggregateStatus.Disconnected:
                StatusIcon.Glyph = "\uE7BA"; // Warning
                StatusIcon.Foreground = new SolidColorBrush(Color.FromArgb(0xFF, 0xFF, 0x95, 0x00));
                StatusIcon.Visibility = Visibility.Visible;
                break;
            default:
                StatusIcon.Visibility = Visibility.Collapsed;
                break;
        }
    }

    private static UIElement EmptyState(string title, string actionTitle, RoutedEventHandler action)
    {
        var panel = new StackPanel
        {
            Spacing = 10,
            HorizontalAlignment = HorizontalAlignment.Center,
            Margin = new Thickness(0, 28, 0, 28),
        };
        panel.Children.Add(new TextBlock
        {
            Text = title,
            Foreground = (Brush)Application.Current.Resources["TextFillColorSecondaryBrush"],
            HorizontalAlignment = HorizontalAlignment.Center,
        });
        var button = new Button { Content = actionTitle };
        button.Click += action;
        panel.Children.Add(button);
        return panel;
    }

    private void Settings_Click(object sender, RoutedEventArgs e) =>
        (App.MainWindowInstance as MainWindow)?.NavigateToSettings();

    private async void Refresh_Click(object sender, RoutedEventArgs e) =>
        await App.Store.RefreshNowAsync();

    private async void Feedback_Click(object sender, RoutedEventArgs e)
    {
        var box = new TextBox { PlaceholderText = "Optional feedback", AcceptsReturn = true, Height = 100 };
        var dialog = new ContentDialog
        {
            Title = "Send feedback",
            Content = box,
            PrimaryButtonText = "Send",
            CloseButtonText = "Cancel",
            XamlRoot = XamlRoot,
        };
        var result = await dialog.ShowAsync();
        if (result == ContentDialogResult.Primary && App.Analytics.IsEnabled)
        {
            App.Analytics.Capture("feedback_submitted", new Dictionary<string, object>
            {
                ["has_message"] = !string.IsNullOrWhiteSpace(box.Text),
                ["message_length_bucket"] = box.Text.Length switch
                {
                    0 => "0",
                    <= 50 => "1-50",
                    <= 200 => "51-200",
                    _ => "200+",
                },
            });
        }
    }

    private async void Update_Click(object sender, RoutedEventArgs e)
    {
        try
        {
            var found = await App.Updater.CheckForUpdatesAsync();
            if (!found)
            {
                var dialog = new ContentDialog
                {
                    Title = "You're up to date",
                    Content = $"Toast {Helpers.AppConfig.Current.AppVersion} is the latest version.",
                    CloseButtonText = "OK",
                    XamlRoot = XamlRoot,
                };
                await dialog.ShowAsync();
            }
        }
        catch (Exception ex)
        {
            var dialog = new ContentDialog
            {
                Title = "Update check failed",
                Content = ex.Message,
                CloseButtonText = "OK",
                XamlRoot = XamlRoot,
            };
            await dialog.ShowAsync();
        }
    }

    private void Quit_Click(object sender, RoutedEventArgs e) =>
        (Application.Current as App)?.QuitFromUser();
}
