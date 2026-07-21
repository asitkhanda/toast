using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Toast.Core.Models;
using Toast.Core.Store;

namespace Toast.Views;

public sealed partial class OnboardingPage : Page
{
    private int _step;
    private List<WatchedProject> _selectedProjects = [];

    public OnboardingPage()
    {
        InitializeComponent();
        Loaded += (_, _) => RefreshStep();
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
                await Store.ConnectAsync(TokenBox.Password);
                TokenBox.Password = string.Empty;
                if (!string.IsNullOrEmpty(Store.TokenScopeWarning))
                {
                    ScopeWarning.Text = Store.TokenScopeWarning;
                    ScopeWarning.Visibility = Visibility.Visible;
                }

                _step = 1;
                await Store.ReloadProjectsAsync();
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
        var teamId = Store.SelectedTeamId ?? "";
        foreach (var project in Store.Projects)
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
                });
            }
        }

        return list;
    }

    private void RefreshStep()
    {
        var onToken = _step == 0;
        TokenHelpText.Visibility = onToken ? Visibility.Visible : Visibility.Collapsed;
        TokenBox.Visibility = onToken ? Visibility.Visible : Visibility.Collapsed;
        TokenHelpLink.Visibility = onToken ? Visibility.Visible : Visibility.Collapsed;
        ProjectList.Visibility = _step == 1 ? Visibility.Visible : Visibility.Collapsed;
        BackgroundPanel.Visibility = _step == 2 ? Visibility.Visible : Visibility.Collapsed;
        StepTitle.Text = _step switch
        {
            0 => "Connect your Vercel token",
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
