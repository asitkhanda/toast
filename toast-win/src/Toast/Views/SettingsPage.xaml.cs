using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Toast.Core.Models;
using Toast.Helpers;

namespace Toast.Views;

public sealed partial class SettingsPage : Page
{
    private bool _loading = true;
    private bool _binding;
    private DeploymentProvider _provider = DeploymentProvider.Vercel;

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

    private void Provider_Checked(object sender, RoutedEventArgs e)
    {
        if (_loading)
        {
            return;
        }

        _provider = CloudflareOption.IsChecked == true ? DeploymentProvider.Cloudflare : DeploymentProvider.Vercel;
        TokenBox.Password = string.Empty;
        ErrorText.Visibility = Visibility.Collapsed;
        Bind();
    }

    private void Bind()
    {
        _binding = true;
        try
        {
            BindCore();
        }
        finally
        {
            _binding = false;
        }
    }

    private void BindCore()
    {
        var store = App.Store;
        var provider = _provider;
        var hasToken = store.HasTokenFor(provider);
        var accountName = store.ConnectedAccountNameFor(provider);
        ConnectionStatus.Text = store.IsConnectedTo(provider)
            ? $"Token saved in Credential Manager{(accountName is { } n ? $" · {n}" : "")}"
            : hasToken
                ? $"Toast can't reach {provider.DisplayName()} with the saved token. Replace it below."
                : "Not connected";
        TokenBox.PlaceholderText = hasToken
            ? $"Replace {provider.DisplayName()} token"
            : provider.TokenPlaceholder();

        var warning = store.ScopeWarningFor(provider);
        ScopeWarning.Text = warning ?? "";
        ScopeWarning.Visibility = string.IsNullOrEmpty(warning) ? Visibility.Collapsed : Visibility.Visible;

        ShowStatusTextToggle.IsOn = store.ShowStatusText;
        NotificationsToggle.IsOn = store.NotificationsEnabled;
        LaunchAtLoginToggle.IsOn = store.LaunchAtLoginEnabled;
        RunInBackgroundToggle.IsOn = store.RunInBackgroundEnabled;
        RelaunchOnCrashToggle.IsOn = store.RelaunchOnCrashEnabled;
        AnalyticsToggle.IsOn = App.Analytics.IsEnabled;
        UpdateButton.Visibility = App.Updater.SupportsManualUpdates
            ? Visibility.Visible
            : Visibility.Collapsed;

        var accounts = store.AccountsFor(provider);
        AccountPicker.Header = provider.AccountNoun();
        AccountPicker.ItemsSource = accounts.ToList();
        AccountPicker.DisplayMemberPath = nameof(Team.DisplayName);
        AccountPicker.SelectedItem = accounts.FirstOrDefault(a => a.Id == store.SelectedAccountIdFor(provider));
        AccountPicker.Visibility = accounts.Count > 1 ? Visibility.Visible : Visibility.Collapsed;

        var notice = store.ProjectNoticeFor(provider);
        ProjectNotice.Text = notice ?? "";
        ProjectNotice.Visibility = string.IsNullOrEmpty(notice) ? Visibility.Collapsed : Visibility.Visible;

        ProjectList.Items.Clear();
        var watched = store.WatchedProjects
            .Where(w => w.Provider == provider)
            .Select(w => w.ProjectId)
            .ToHashSet();
        var teamId = store.SelectedAccountIdFor(provider) ?? "";
        foreach (var project in store.ProjectsFor(provider))
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

    private async void AccountPicker_SelectionChanged(object sender, SelectionChangedEventArgs e)
    {
        if (_binding || _loading || AccountPicker.SelectedItem is not Team team)
        {
            return;
        }

        App.Store.SelectAccount(team.Id, _provider);
        await App.Store.ReloadProjectsAsync(_provider);
        Bind();
    }

    private async void ReloadProjects_Click(object sender, RoutedEventArgs e)
    {
        await App.Store.ReloadProjectsAsync(_provider);
        Bind();
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
            await App.Store.ConnectAsync(TokenBox.Password, _provider);
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
        App.Store.Disconnect(_provider);
        if (App.Store.HasCompletedOnboarding)
        {
            Bind();
        }
        else
        {
            (App.MainWindowInstance as MainWindow)?.NavigateToOnboarding();
        }
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
                    Provider = _provider,
                });
            }
        }

        App.Store.UpdateWatchedProjects(selected, _provider);
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

    private async void Update_Click(object sender, RoutedEventArgs e)
    {
        UpdateButton.IsEnabled = false;
        try
        {
            var found = await App.Updater.CheckForUpdatesAsync();
            if (!found)
            {
                var dialog = new ContentDialog
                {
                    Title = "You're up to date",
                    Content = $"Toast {AppConfig.Current.AppVersion} is the latest version.",
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
        finally
        {
            UpdateButton.IsEnabled = true;
        }
    }

    private sealed class ProjectPick
    {
        public string ProjectId { get; set; } = "";
        public string ProjectName { get; set; } = "";
        public string TeamId { get; set; } = "";
        public string Display { get; set; } = "";
    }
}
