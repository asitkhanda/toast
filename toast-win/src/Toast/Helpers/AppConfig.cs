using System.Text.Json;
using System.Reflection;

namespace Toast.Helpers;

public sealed class AppConfig
{
    public static AppConfig Current { get; private set; } = Load();

    public string PostHogApiKey { get; set; } = "";
    public string PostHogHost { get; set; } = "https://us.i.posthog.com";
    public string UpdateUrl { get; set; } = "https://github.com/asitkhanda/toast";
    public string AppVersion { get; set; } = "0.0.0";
    public string AppBuild { get; set; } = "0";
    public string ExecutablePath { get; set; } = Environment.ProcessPath ?? "";

    public static void Reload() => Current = Load();

    private static AppConfig Load()
    {
        var config = new AppConfig();
        try
        {
            var baseDir = AppContext.BaseDirectory;
            var path = Path.Combine(baseDir, "appsettings.json");
            if (File.Exists(path))
            {
                var json = File.ReadAllText(path);
                var loaded = JsonSerializer.Deserialize<AppConfig>(json, new JsonSerializerOptions
                {
                    PropertyNameCaseInsensitive = true,
                });
                if (loaded is not null)
                {
                    config = loaded;
                }
            }
        }
        catch
        {
            // Use defaults.
        }

        var assemblyVersion = Assembly.GetEntryAssembly()?.GetName().Version;
        if (assemblyVersion is not null)
        {
            config.AppVersion = string.Join(".", assemblyVersion.Major, assemblyVersion.Minor, assemblyVersion.Build);
            config.AppBuild = Math.Max(assemblyVersion.Revision, 0).ToString();
        }

        config.ExecutablePath = Environment.ProcessPath ?? "";
        return config;
    }
}
