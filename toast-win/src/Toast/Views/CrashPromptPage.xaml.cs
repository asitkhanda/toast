using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;

namespace Toast.Views;

public sealed partial class CrashPromptPage : Page
{
    public CrashPromptPage() => InitializeComponent();

    private void Continue_Click(object sender, RoutedEventArgs e)
    {
        if (DontShowAgain.IsChecked == true)
        {
            App.Analytics.SuppressCrashPrompt(true);
        }

        if (App.Store.HasCompletedOnboarding)
        {
            (App.MainWindowInstance as MainWindow)?.NavigateToPopover();
        }
        else
        {
            (App.MainWindowInstance as MainWindow)?.NavigateToOnboarding();
        }
    }
}
