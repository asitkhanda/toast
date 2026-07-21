using System.Text.Json;

namespace Toast.Helpers;

public sealed class AppConfig
{
    public static AppConfig Current { get; private set; } = Load();

    public string PostHogApiKey { get; set; } = "";
    public string PostHogHost { get; set; } = "https://us.i.posthog.com";
    public string UpdateUrl { get; set; } = "https://github.com/asitkhanda/toast";
    public string AppVersion { get; set; } = "0.4.1";
    public string AppBuild { get; set; } = "11";
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

        config.ExecutablePath = Environment.ProcessPath ?? "";
        return config;
    }
}
