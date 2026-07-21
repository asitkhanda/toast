using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Toast.Core.Models;

namespace Toast.Views;

public sealed partial class SettingsPage : Page
{
    private bool _loading = true;

    public SettingsPage()
    {
        InitializeComponent();
        Loaded += async (_, _) =>
        {
            await App.Store.RestoreSessionIfNeededAsync();
            Bind();
            _loading = false;
        };
    }

    private void Bind()
    {
        var store = App.Store;
        ConnectionStatus.Text = store.IsConnected
            ? $"Token saved in Credential Manager{(store.ConnectedTeamName is { } n ? $" · {n}" : "")}"
            : "Not connected";
        ScopeWarning.Text = store.TokenScopeWarning ?? "";
        ScopeWarning.Visibility = string.IsNullOrEmpty(store.TokenScopeWarning)
            ? Visibility.Collapsed
            : Visibility.Visible;

        ShowStatusTextToggle.IsOn = store.ShowStatusText;
        NotificationsToggle.IsOn = store.NotificationsEnabled;
        LaunchAtLoginToggle.IsOn = store.LaunchAtLoginEnabled;
        RunInBackgroundToggle.IsOn = store.RunInBackgroundEnabled;
        RelaunchOnCrashToggle.IsOn = store.RelaunchOnCrashEnabled;
        AnalyticsToggle.IsOn = App.Analytics.IsEnabled;
        UpdateButton.Visibility = App.Updater.SupportsManualUpdates
            ? Visibility.Visible
            : Visibility.Collapsed;

        ProjectList.Items.Clear();
        var watched = store.WatchedProjects.Select(w => w.ProjectId).ToHashSet();
        var teamId = store.SelectedTeamId ?? "";
        foreach (var project in store.Projects)
        {
            var item = new ProjectPick
            {
                ProjectId = project.Id,
                ProjectName = project.Name,
                TeamId = teamId,
                Display = project.DisplayName,
            };
            ProjectList.Items.Add(item);
            if (watched.Contains(project.Id))
            {
                ProjectList.SelectedItems.Add(item);
            }
        }

        ProjectList.DisplayMemberPath = nameof(ProjectPick.Display);
    }

    private void Back_Click(object sender, RoutedEventArgs e)
    {
        if (App.Store.HasCompletedOnboarding)
        {
            (App.MainWindowInstance as MainWindow)?.NavigateToPopover();
        }
        else
        {
            (App.MainWindowInstance as MainWindow)?.NavigateToOnboarding();
        }
    }

    private async void SaveToken_Click(object sender, RoutedEventArgs e)
    {
        ErrorText.Visibility = Visibility.Collapsed;
        try
        {
            await App.Store.ConnectAsync(TokenBox.Password);
            TokenBox.Password = string.Empty;
            Bind();
        }
        catch (Exception ex)
        {
            ErrorText.Text = ex.Message;
            ErrorText.Visibility = Visibility.Visible;
        }
    }

    private void Disconnect_Click(object sender, RoutedEventArgs e)
    {
        App.Store.Disconnect();
        (App.MainWindowInstance as MainWindow)?.NavigateToOnboarding();
    }

    private void SaveProjects_Click(object sender, RoutedEventArgs e)
    {
        var selected = new List<WatchedProject>();
        foreach (var item in ProjectList.SelectedItems)
        {
            if (item is ProjectPick pick)
            {
                selected.Add(new WatchedProject
                {
                    ProjectId = pick.ProjectId,
                    ProjectName = pick.ProjectName,
                    TeamId = pick.TeamId,
                });
            }
        }

        App.Store.UpdateWatchedProjects(selected);
    }

    private void Pref_Toggled(object sender, RoutedEventArgs e)
    {
        if (_loading)
        {
            return;
        }

        App.Store.ShowStatusText = ShowStatusTextToggle.IsOn;
        App.Store.NotificationsEnabled = NotificationsToggle.IsOn;
        App.Store.LaunchAtLoginEnabled = LaunchAtLoginToggle.IsOn;
        App.Store.RunInBackgroundEnabled = RunInBackgroundToggle.IsOn;
        App.Store.RelaunchOnCrashEnabled = RelaunchOnCrashToggle.IsOn;
    }

    private void Analytics_Toggled(object sender, RoutedEventArgs e)
    {
        if (_loading)
        {
            return;
        }

        App.Analytics.IsEnabled = AnalyticsToggle.IsOn;
    }

    private async void Update_Click(object sender, RoutedEventArgs e) =>
        await App.Updater.CheckForUpdatesAsync();

    private sealed class ProjectPick
    {
        public string ProjectId { get; set; } = "";
        public string ProjectName { get; set; } = "";
        public string TeamId { get; set; } = "";
        public string Display { get; set; } = "";
    }
}
