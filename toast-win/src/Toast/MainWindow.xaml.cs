using Microsoft.UI.Xaml;
using Toast.Views;
using Windows.Graphics;

namespace Toast;

public sealed partial class MainWindow : Window
{
    public MainWindow()
    {
        InitializeComponent();
        ExtendsContentIntoTitleBar = true;
        Title = "Toast";

        // WinUI Window has no Width/Height XAML props — size via AppWindow.
        AppWindow.Resize(new SizeInt32(420, 620));
    }

    public void NavigateToOnboarding() => RootFrame.Navigate(typeof(OnboardingPage));

    public void NavigateToPopover() => RootFrame.Navigate(typeof(PopoverPage));

    public void NavigateToSettings() => RootFrame.Navigate(typeof(SettingsPage));

    public void ShowCrashPrompt() => RootFrame.Navigate(typeof(CrashPromptPage));

    public void ShowAnalyticsNotice() => RootFrame.Navigate(typeof(AnalyticsNoticePage));

    public void ShowUpdateAvailable(string version) =>
        RootFrame.Navigate(typeof(UpdateAvailablePage), version);
}
