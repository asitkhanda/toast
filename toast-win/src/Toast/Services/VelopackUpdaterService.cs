using Toast.Core.Services;
using Toast.Helpers;
using Velopack;
using Velopack.Sources;

namespace Toast.Services;

public sealed class VelopackUpdaterService : IUpdaterService
{
    private readonly UpdateManager? _manager;

    public VelopackUpdaterService(AppConfig config)
    {
        try
        {
            var source = new GithubSource(config.UpdateUrl, "", prerelease: false);
            _manager = new UpdateManager(source);
        }
        catch
        {
            _manager = null;
        }
    }

    public bool SupportsManualUpdates => _manager?.IsInstalled == true;

    public async Task CheckForUpdatesAsync()
    {
        if (_manager is null || !_manager.IsInstalled)
        {
            return;
        }

        var update = await _manager.CheckForUpdatesAsync();
        if (update is null)
        {
            return;
        }

        await _manager.DownloadUpdatesAsync(update);
        _manager.ApplyUpdatesAndRestart(update);
    }
}
