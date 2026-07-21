using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Navigation;

namespace Toast.Views;

public sealed partial class UpdateAvailablePage : Page
{
    private string _version = "";

    public UpdateAvailablePage() => InitializeComponent();

    protected override void OnNavigatedTo(NavigationEventArgs e)
    {
        base.OnNavigatedTo(e);
        _version = e.Parameter as string
            ?? App.Updater.PendingVersion
            ?? "a newer version";
        VersionText.Text = $"Toast {_version} is ready to install.";
    }

    protected override void OnNavigatedFrom(NavigationEventArgs e)
    {
        base.OnNavigatedFrom(e);
        App.Updater.MarkPromptClosed();
    }

    private async void Download_Click(object sender, RoutedEventArgs e)
    {
        SetBusy(true, "Downloading update…");
        try
        {
            if (App.Analytics.IsEnabled)
            {
                App.Analytics.Capture("update_download_started", new Dictionary<string, object>
                {
                    ["to_version"] = _version,
                });
            }

            await App.Updater.DownloadAndRestartAsync();
            // If ApplyUpdatesAndRestart returns without exiting, surface a message.
            SetBusy(false, "Update applied — restart Toast if it doesn’t reopen.");
        }
        catch (Exception ex)
        {
            SetBusy(false, $"Update failed: {ex.Message}");
        }
    }

    private void Skip_Click(object sender, RoutedEventArgs e)
    {
        App.Updater.SkipPendingVersion();
        if (App.Analytics.IsEnabled)
        {
            App.Analytics.Capture("update_skipped", new Dictionary<string, object>
            {
                ["version"] = _version,
                ["skip_days"] = 7,
            });
        }

        Dismiss();
    }

    private void Dismiss()
    {
        App.Updater.MarkPromptClosed();
        if (App.Store.HasCompletedOnboarding)
        {
            (App.MainWindowInstance as MainWindow)?.NavigateToPopover();
        }
        else
        {
            (App.MainWindowInstance as MainWindow)?.NavigateToOnboarding();
        }
    }

    private void SetBusy(bool busy, string? status)
    {
        DownloadButton.IsEnabled = !busy;
        SkipButton.IsEnabled = !busy;
        Progress.Visibility = busy ? Visibility.Visible : Visibility.Collapsed;
        if (string.IsNullOrWhiteSpace(status))
        {
            StatusText.Visibility = Visibility.Collapsed;
        }
        else
        {
            StatusText.Text = status;
            StatusText.Visibility = Visibility.Visible;
        }
    }
}
