using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Toast.Core.Models;

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
        HeaderTitle.Text = store.ConnectedTeamName is { Length: > 0 } name
            ? name
            : "Toast";
        HeaderSubtitle.Text = store.LastError
            ?? (store.IsConnected ? "Live deployment status" : "Disconnected — reconnect in Settings");

        StatusList.Items.Clear();
        foreach (var status in store.ProjectStatuses)
        {
            var state = status.Status.DisplayName();
            var commit = status.Deployment?.CommitMessage;
            var line = string.IsNullOrWhiteSpace(commit)
                ? $"{status.Watched.ProjectName} — {state}"
                : $"{status.Watched.ProjectName} — {state}\n{commit}";
            StatusList.Items.Add(line);
        }

        if (store.ProjectStatuses.Count == 0)
        {
            StatusList.Items.Add("No watched projects yet.");
        }
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

    private async void Update_Click(object sender, RoutedEventArgs e) =>
        await App.Updater.CheckForUpdatesAsync();
}
