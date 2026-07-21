using System.Diagnostics;
using Microsoft.Win32;
using Toast.Core.Services;
using Toast.Helpers;

namespace Toast.Services;

public sealed class WindowsBackgroundService : IBackgroundService
{
    private const string RunKeyPath = @"Software\Microsoft\Windows\CurrentVersion\Run";
    private const string ValueName = "Toast";
    private readonly IPreferencesStore _prefs;
    private readonly string _runtimePath;

    public WindowsBackgroundService(IPreferencesStore prefs)
    {
        _prefs = prefs;
        var dir = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
            "Toast");
        Directory.CreateDirectory(dir);
        _runtimePath = Path.Combine(dir, "runtime.json");
    }

    public void MarkAppRunning()
    {
        WriteRuntime(userQuit: false, running: true);
    }

    public void MarkUserQuit()
    {
        WriteRuntime(userQuit: true, running: false);
    }

    public void Sync(bool launchAtLogin, bool runInBackground, bool relaunchOnCrash)
    {
        _prefs.SetBool("relaunchOnCrash", relaunchOnCrash);
        SetLaunchAtLogin(launchAtLogin);
        SyncWatchdog(relaunchOnCrash);
        // runInBackground on Windows means stay tray-only (no taskbar window) — handled by App.
    }

    private void SyncWatchdog(bool enabled)
    {
        try
        {
            foreach (var existing in Process.GetProcessesByName("Toast.Watchdog"))
            {
                try
                {
                    existing.Kill();
                }
                catch
                {
                    // Ignore.
                }
            }

            if (!enabled)
            {
                return;
            }

            var mainExe = Environment.ProcessPath;
            if (string.IsNullOrWhiteSpace(mainExe))
            {
                return;
            }

            var watchdog = Path.Combine(AppContext.BaseDirectory, "Toast.Watchdog.exe");
            if (!File.Exists(watchdog))
            {
                return;
            }

            Process.Start(new ProcessStartInfo
            {
                FileName = watchdog,
                Arguments = $"\"{mainExe}\"",
                UseShellExecute = false,
                CreateNoWindow = true,
            });
        }
        catch
        {
            // Watchdog is best-effort.
        }
    }

    public bool WasUnexpectedExit()
    {
        try
        {
            if (!File.Exists(_runtimePath))
            {
                return false;
            }

            var json = File.ReadAllText(_runtimePath);
            return json.Contains("\"userQuit\":false", StringComparison.Ordinal)
                && json.Contains("\"running\":true", StringComparison.Ordinal);
        }
        catch
        {
            return false;
        }
    }

    private void SetLaunchAtLogin(bool enabled)
    {
        try
        {
            using var key = Registry.CurrentUser.OpenSubKey(RunKeyPath, writable: true)
                ?? Registry.CurrentUser.CreateSubKey(RunKeyPath);
            if (key is null)
            {
                return;
            }

            if (enabled)
            {
                var exe = Environment.ProcessPath ?? AppConfig.Current.ExecutablePath;
                key.SetValue(ValueName, $"\"{exe}\"");
            }
            else
            {
                key.DeleteValue(ValueName, throwOnMissingValue: false);
            }
        }
        catch
        {
            // Startup registration can fail under restricted policies.
        }
    }

    private void WriteRuntime(bool userQuit, bool running)
    {
        try
        {
            var json = $"{{\"userQuit\":{(userQuit ? "true" : "false")},\"running\":{(running ? "true" : "false")}}}";
            File.WriteAllText(_runtimePath, json);
        }
        catch
        {
            // Best-effort.
        }
    }
}
