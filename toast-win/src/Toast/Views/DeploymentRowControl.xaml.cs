using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;
using Toast.Core.Models;
using Toast.Core.Store;
using Toast.Helpers;
using Windows.System;
using Windows.UI;

namespace Toast.Views;

public sealed partial class DeploymentRowControl : UserControl
{
    private ProjectDeploymentStatus? _status;
    private Uri? _previewUri;
    private Uri? _dashboardUri;

    public DeploymentRowControl() => InitializeComponent();

    public void Bind(ProjectDeploymentStatus status, bool showProjectName = true)
    {
        _status = status;
        var deployment = status.Deployment;

        ProjectNameText.Text = showProjectName
            ? status.Watched.ProjectName
            : status.Status.DisplayName();
        ProjectNameText.Visibility = showProjectName ? Visibility.Visible : Visibility.Collapsed;

        ApplyStatusBadge(status.Status);

        var deployed = RelativeDateFormat.FromUnixMs(deployment?.Ready ?? deployment?.CreatedAt);
        if (deployed is not null)
        {
            DeployedText.Text = RelativeDateFormat.Label(deployed.Value, "Deployed");
            DeployedText.Visibility = Visibility.Visible;
        }
        else
        {
            DeployedText.Visibility = Visibility.Collapsed;
        }

        CheckedText.Text = RelativeDateFormat.Label(status.FetchedAt, "Checked");

        if (deployment is null)
        {
            MetaRow.Visibility = Visibility.Collapsed;
            CommitText.Visibility = Visibility.Collapsed;
            ActionsRow.Visibility = Visibility.Collapsed;
            EmptyText.Visibility = Visibility.Visible;
            return;
        }

        EmptyText.Visibility = Visibility.Collapsed;
        MetaRow.Visibility = Visibility.Visible;

        ProductionTag.Visibility = deployment.IsProduction ? Visibility.Visible : Visibility.Collapsed;

        if (!string.IsNullOrWhiteSpace(deployment.Branch))
        {
            BranchText.Text = deployment.Branch;
            BranchTag.Visibility = Visibility.Visible;
        }
        else
        {
            BranchTag.Visibility = Visibility.Collapsed;
        }

        if (!string.IsNullOrWhiteSpace(deployment.CommitSha))
        {
            ShaText.Text = deployment.CommitSha;
            ShaText.Visibility = Visibility.Visible;
        }
        else
        {
            ShaText.Visibility = Visibility.Collapsed;
        }

        if (!string.IsNullOrWhiteSpace(deployment.CommitMessage))
        {
            CommitText.Text = deployment.CommitMessage;
            CommitText.Visibility = Visibility.Visible;
        }
        else
        {
            CommitText.Visibility = Visibility.Collapsed;
        }

        ActionsRow.Visibility = Visibility.Visible;
        _previewUri = deployment.PreviewUrl;
        PreviewLink.Visibility = _previewUri is null ? Visibility.Collapsed : Visibility.Visible;
        _dashboardUri = new Uri(
            $"https://vercel.com/{status.Watched.TeamId}/{Uri.EscapeDataString(status.Watched.ProjectName)}/{deployment.Uid}");
    }

    private void ApplyStatusBadge(DeploymentState state)
    {
        StatusBadgeText.Text = state.DisplayName();
        var (fill, text) = state switch
        {
            DeploymentState.Ready => (Color.FromArgb(0x26, 0x34, 0xC7, 0x59), Color.FromArgb(0xFF, 0x34, 0xC7, 0x59)),
            DeploymentState.Building or DeploymentState.Initializing or DeploymentState.Queued
                => (Color.FromArgb(0x26, 0x00, 0x7A, 0xFF), Color.FromArgb(0xFF, 0x00, 0x7A, 0xFF)),
            DeploymentState.Error or DeploymentState.Canceled or DeploymentState.Blocked
                => (Color.FromArgb(0x26, 0xFF, 0x3B, 0x30), Color.FromArgb(0xFF, 0xFF, 0x3B, 0x30)),
            _ => (Color.FromArgb(0x26, 0x8E, 0x8E, 0x93), Color.FromArgb(0xFF, 0x8E, 0x8E, 0x93)),
        };
        StatusBadge.Background = new SolidColorBrush(fill);
        StatusBadgeText.Foreground = new SolidColorBrush(text);
    }

    private async void PreviewLink_Click(object sender, RoutedEventArgs e)
    {
        if (_previewUri is not null)
        {
            await Launcher.LaunchUriAsync(_previewUri);
        }
    }

    private async void DashboardLink_Click(object sender, RoutedEventArgs e)
    {
        if (_dashboardUri is not null)
        {
            await Launcher.LaunchUriAsync(_dashboardUri);
        }
    }
}
