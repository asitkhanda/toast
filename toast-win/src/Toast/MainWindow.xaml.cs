using Microsoft.UI.Xaml;
using Toast.Views;

namespace Toast;

public sealed partial class MainWindow : Window
{
    public MainWindow()
    {
        InitializeComponent();
        ExtendsContentIntoTitleBar = true;
    }

    public void NavigateToOnboarding() => RootFrame.Navigate(typeof(OnboardingPage));

    public void NavigateToPopover() => RootFrame.Navigate(typeof(PopoverPage));

    public void NavigateToSettings() => RootFrame.Navigate(typeof(SettingsPage));

    public void ShowCrashPrompt() => RootFrame.Navigate(typeof(CrashPromptPage));

    public void ShowAnalyticsNotice() => RootFrame.Navigate(typeof(AnalyticsNoticePage));
}
