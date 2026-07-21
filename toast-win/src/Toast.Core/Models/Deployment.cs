using System.Text.Json.Serialization;

namespace Toast.Core.Models;

public enum DeploymentState
{
    Queued,
    Initializing,
    Building,
    Ready,
    Error,
    Canceled,
    Blocked,
}

public static class DeploymentStateExtensions
{
    public static bool IsInProgress(this DeploymentState state) =>
        state is DeploymentState.Queued or DeploymentState.Initializing or DeploymentState.Building;

    public static bool IsTerminal(this DeploymentState state) =>
        state is DeploymentState.Ready or DeploymentState.Error or DeploymentState.Canceled or DeploymentState.Blocked;

    public static string DisplayName(this DeploymentState state) => state switch
    {
        DeploymentState.Queued => "Queued",
        DeploymentState.Initializing => "Initializing",
        DeploymentState.Building => "Building",
        DeploymentState.Ready => "Ready",
        DeploymentState.Error => "Error",
        DeploymentState.Canceled => "Canceled",
        DeploymentState.Blocked => "Blocked",
        _ => state.ToString(),
    };

    public static DeploymentState Parse(string? value) => value?.ToUpperInvariant() switch
    {
        "QUEUED" => DeploymentState.Queued,
        "INITIALIZING" => DeploymentState.Initializing,
        "BUILDING" => DeploymentState.Building,
        "READY" => DeploymentState.Ready,
        "ERROR" => DeploymentState.Error,
        "CANCELED" or "CANCELLED" => DeploymentState.Canceled,
        "BLOCKED" => DeploymentState.Blocked,
        _ => DeploymentState.Queued,
    };
}

public sealed class DeploymentMeta
{
    [JsonPropertyName("githubCommitMessage")]
    public string? GithubCommitMessage { get; set; }

    [JsonPropertyName("githubCommitRef")]
    public string? GithubCommitRef { get; set; }

    [JsonPropertyName("githubCommitSha")]
    public string? GithubCommitSha { get; set; }

    [JsonPropertyName("githubCommitAuthorName")]
    public string? GithubCommitAuthorName { get; set; }
}

public sealed class DeploymentCreator
{
    [JsonPropertyName("username")]
    public string? Username { get; set; }
}

public sealed class Deployment
{
    [JsonPropertyName("uid")]
    public string Uid { get; set; } = "";

    [JsonPropertyName("name")]
    public string Name { get; set; } = "";

    [JsonPropertyName("url")]
    public string? Url { get; set; }

    [JsonPropertyName("state")]
    public string? StateRaw { get; set; }

    [JsonPropertyName("readyState")]
    public string? ReadyStateRaw { get; set; }

    [JsonPropertyName("target")]
    public string? Target { get; set; }

    [JsonPropertyName("createdAt")]
    public double? CreatedAt { get; set; }

    [JsonPropertyName("buildingAt")]
    public double? BuildingAt { get; set; }

    [JsonPropertyName("ready")]
    public double? Ready { get; set; }

    [JsonPropertyName("meta")]
    public DeploymentMeta? Meta { get; set; }

    [JsonPropertyName("creator")]
    public DeploymentCreator? Creator { get; set; }

    public DeploymentState Status =>
        DeploymentStateExtensions.Parse(ReadyStateRaw ?? StateRaw);

    public string? CommitMessage => Meta?.GithubCommitMessage;

    public string? Branch => Meta?.GithubCommitRef;

    public string? CommitSha => Meta?.GithubCommitSha is { Length: > 0 } sha
        ? sha[..Math.Min(7, sha.Length)]
        : null;

    public bool IsProduction =>
        string.Equals(Target, "production", StringComparison.OrdinalIgnoreCase);

    public Uri? PreviewUrl
    {
        get
        {
            if (string.IsNullOrWhiteSpace(Url))
            {
                return null;
            }

            if (Url.StartsWith("http", StringComparison.OrdinalIgnoreCase))
            {
                return Uri.TryCreate(Url, UriKind.Absolute, out var absolute) ? absolute : null;
            }

            return Uri.TryCreate($"https://{Url}", UriKind.Absolute, out var https) ? https : null;
        }
    }
}

public sealed class DeploymentsResponse
{
    [JsonPropertyName("deployments")]
    public List<Deployment> Deployments { get; set; } = [];
}
