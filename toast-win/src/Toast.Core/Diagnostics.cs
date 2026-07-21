namespace Toast.Core;

public static class Diagnostics
{
    public static string ProjectsWatchedBucket(int count) => count switch
    {
        0 => "0",
        1 => "1",
        >= 2 and <= 5 => "2-5",
        _ => "6+",
    };

    public static string CurrentArchitecture()
    {
        return System.Runtime.InteropServices.RuntimeInformation.ProcessArchitecture switch
        {
            System.Runtime.InteropServices.Architecture.X64 => "x64",
            System.Runtime.InteropServices.Architecture.Arm64 => "arm64",
            System.Runtime.InteropServices.Architecture.X86 => "x86",
            _ => "unknown",
        };
    }

    public static Dictionary<string, object> Snapshot(
        bool onboardingCompleted,
        int projectsWatched,
        bool launchAtLogin,
        bool runInBackground,
        bool relaunchOnCrash,
        bool notificationsEnabled,
        bool showStatusText,
        bool analyticsEnabled,
        string appVersion,
        string build,
        bool launcherRelaunch = false)
    {
        return new Dictionary<string, object>
        {
            ["app_version"] = appVersion,
            ["build"] = build,
            ["os_version"] = Environment.OSVersion.VersionString,
            ["arch"] = CurrentArchitecture(),
            ["onboarding_completed"] = onboardingCompleted,
            ["projects_watched_bucket"] = ProjectsWatchedBucket(projectsWatched),
            ["launch_at_login"] = launchAtLogin,
            ["run_in_background"] = runInBackground,
            ["relaunch_on_crash"] = relaunchOnCrash,
            ["notifications_enabled"] = notificationsEnabled,
            ["show_status_text"] = showStatusText,
            ["analytics_enabled"] = analyticsEnabled,
            ["launcher_relaunch"] = launcherRelaunch,
        };
    }
}
