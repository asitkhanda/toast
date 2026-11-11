using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Toast.Core.Models;
using Toast.Core.Store;

namespace Toast.Views;

public sealed partial class OnboardingPage : Page
{
    private int _step;
    private bool _ready;
    private DeploymentProvider _provider = DeploymentProvider.Vercel;
    private List<WatchedProject> _selectedProjects = [];

    public OnboardingPage()
    {
        InitializeComponent();
        _ready = true;
        Loaded += (_, _) => RefreshStep();
    }

    private void Provider_Checked(object sender, RoutedEventArgs e)
    {
        if (!_ready)
        {
            return;
        }

        _provider = CloudflareOption.IsChecked == true ? DeploymentProvider.Cloudflare : DeploymentProvider.Vercel;
        TokenBox.Password = string.Empty;
        ErrorText.Visibility = Visibility.Collapsed;
        ScopeWarning.Visibility = Visibility.Collapsed;
        RefreshStep();
    }

    private DeploymentStore Store => App.Store;

    private async void PrimaryButton_Click(object sender, RoutedEventArgs e)
    {
        ErrorText.Visibility = Visibility.Collapsed;
        try
        {
            if (_step == 0)
            {
                PrimaryButton.IsEnabled = false;
                await Store.ConnectAsync(TokenBox.Password, _provider);
                TokenBox.Password = string.Empty;
                if (Store.ScopeWarningFor(_provider) is { Length: > 0 } warning)
                {
                    ScopeWarning.Text = warning;
                    ScopeWarning.Visibility = Visibility.Visible;
                }

                _step = 1;
                await Store.ReloadProjectsAsync(_provider);
                BindProjects();
            }
            else if (_step == 1)
            {
                _selectedProjects = SelectedProjects();
                if (_selectedProjects.Count == 0)
                {
                    ErrorText.Text = "Select at least one project to watch.";
                    ErrorText.Visibility = Visibility.Visible;
                    return;
                }

                _step = 2;
            }
            else
            {
                await Store.CompleteOnboardingAsync(_selectedProjects, new BackgroundPreferences
                {
                    LaunchAtLogin = LaunchAtLoginToggle.IsOn,
                    RunInBackground = RunInBackgroundToggle.IsOn,
                    RelaunchOnCrash = RelaunchOnCrashToggle.IsOn,
                });
                (Application.Current as App)?.StartUpdateChecksAfterOnboarding();
                (App.MainWindowInstance as MainWindow)?.NavigateToPopover();
                return;
            }

            RefreshStep();
        }
        catch (Exception ex)
        {
            // WinRT often prefixes a useless HRESULT string; prefer the inner XAML detail.
            ErrorText.Text = FormatError(ex);
            ErrorText.Visibility = Visibility.Visible;
        }
        finally
        {
            PrimaryButton.IsEnabled = true;
        }
    }

    private void BindProjects()
    {
        ProjectList.Items.Clear();
        var teamId = Store.SelectedAccountIdFor(_provider) ?? "";
        var projects = Store.ProjectsFor(_provider);
        if (projects.Count == 0)
        {
            ErrorText.Text = Store.ProjectNoticeFor(_provider)
                ?? $"No projects found. Check the token's permissions, or pick a different {_provider.AccountNoun().ToLowerInvariant()}.";
            ErrorText.Visibility = Visibility.Visible;
        }

        foreach (var project in projects)
        {
            ProjectList.Items.Add(new ProjectPick
            {
                ProjectId = project.Id,
                ProjectName = project.Name,
                TeamId = teamId,
                Display = project.DisplayName,
            });
        }

        ProjectList.DisplayMemberPath = nameof(ProjectPick.Display);
    }

    private List<WatchedProject> SelectedProjects()
    {
        var list = new List<WatchedProject>();
        foreach (var item in ProjectList.SelectedItems)
        {
            if (item is ProjectPick pick)
            {
                list.Add(new WatchedProject
                {
                    ProjectId = pick.ProjectId,
                    ProjectName = pick.ProjectName,
                    TeamId = pick.TeamId,
                    Provider = _provider,
                });
            }
        }

        return list;
    }

    private void RefreshStep()
    {
        var onToken = _step == 0;
        ProviderPanel.Visibility = onToken ? Visibility.Visible : Visibility.Collapsed;
        TokenHelpText.Text = _provider.TokenAdvice();
        TokenBox.PlaceholderText = _provider.TokenPlaceholder();
        TokenHelpLink.NavigateUri = new Uri(_provider.TokensUrl());
        TokenHelpText.Visibility = onToken ? Visibility.Visible : Visibility.Collapsed;
        TokenBox.Visibility = onToken ? Visibility.Visible : Visibility.Collapsed;
        TokenHelpLink.Visibility = onToken ? Visibility.Visible : Visibility.Collapsed;
        ProjectList.Visibility = _step == 1 ? Visibility.Visible : Visibility.Collapsed;
        BackgroundPanel.Visibility = _step == 2 ? Visibility.Visible : Visibility.Collapsed;
        StepTitle.Text = _step switch
        {
            0 => $"Connect your {_provider.DisplayName()} token",
            1 => "Pick projects to watch",
            _ => "Keep Toast running",
        };
        PrimaryButton.Content = _step == 2 ? "Finish" : "Continue";
    }

    private static string FormatError(Exception ex)
    {
        var candidates = new List<string>();
        for (var current = ex; current is not null; current = current.InnerException)
        {
            if (!string.IsNullOrWhiteSpace(current.Message))
                candidates.Add(current.Message.Trim());
        }

        foreach (var message in candidates)
        {
            if (message.Contains("Cannot find a Resource", StringComparison.OrdinalIgnoreCase)
                || message.Contains("XamlParse", StringComparison.OrdinalIgnoreCase))
            {
                return message;
            }
        }

        foreach (var message in candidates)
        {
            if (!message.Contains("text associated with this error code", StringComparison.OrdinalIgnoreCase))
                return message;
        }

        return ex.GetBaseException().Message;
    }

    private sealed class ProjectPick
    {
        public string ProjectId { get; set; } = "";
        public string ProjectName { get; set; } = "";
        public string TeamId { get; set; } = "";
        public string Display { get; set; } = "";
    }
}
