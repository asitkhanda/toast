using System.Diagnostics;
using System.Text.Json;

namespace Toast.Watchdog;

internal static class Program
{
    private static async Task Main(string[] args)
    {
        var mainExe = args.ElementAtOrDefault(0);
        if (string.IsNullOrWhiteSpace(mainExe) || !File.Exists(mainExe))
        {
            return;
        }

        var runtimePath = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
            "Toast",
            "runtime.json");

        while (true)
        {
            await Task.Delay(TimeSpan.FromSeconds(15));
            try
            {
                var running = Process.GetProcessesByName("Toast")
                    .Any(p =>
                    {
                        try
                        {
                            return string.Equals(p.MainModule?.FileName, mainExe, StringComparison.OrdinalIgnoreCase);
                        }
                        catch
                        {
                            return true;
                        }
                    });

                if (running)
                {
                    continue;
                }

                if (!File.Exists(runtimePath))
                {
                    continue;
                }

                using var doc = JsonDocument.Parse(await File.ReadAllTextAsync(runtimePath));
                var root = doc.RootElement;
                var userQuit = root.TryGetProperty("userQuit", out var u) && u.GetBoolean();
                if (userQuit)
                {
                    return;
                }

                Process.Start(new ProcessStartInfo
                {
                    FileName = mainExe,
                    UseShellExecute = true,
                });
                return;
            }
            catch
            {
                // Keep watching.
            }
        }
    }
}
