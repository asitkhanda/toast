using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;

namespace Toast.Views;

public sealed partial class AnalyticsNoticePage : Page
{
    public AnalyticsNoticePage() => InitializeComponent();

    private void Continue_Click(object sender, RoutedEventArgs e)
    {
        App.Analytics.MarkAnalyticsRolloutNoticeSeen();
        (App.MainWindowInstance as MainWindow)?.NavigateToPopover();
    }
}
