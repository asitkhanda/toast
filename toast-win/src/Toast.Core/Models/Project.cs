using System.Text.Json.Serialization;

namespace Toast.Core.Models;

public sealed class Team
{
    [JsonPropertyName("id")]
    public string Id { get; set; } = "";

    [JsonPropertyName("slug")]
    public string? Slug { get; set; }

    [JsonPropertyName("name")]
    public string? Name { get; set; }

    public string DisplayName => Name ?? Slug ?? Id;
}

public sealed class TeamsResponse
{
    [JsonPropertyName("teams")]
    public List<Team> Teams { get; set; } = [];
}

public sealed class ProjectLink
{
    [JsonPropertyName("type")]
    public string? Type { get; set; }

    [JsonPropertyName("repo")]
    public string? Repo { get; set; }

    [JsonPropertyName("org")]
    public string? Org { get; set; }
}

public sealed class Project
{
    [JsonPropertyName("id")]
    public string Id { get; set; } = "";

    [JsonPropertyName("name")]
    public string Name { get; set; } = "";

    [JsonPropertyName("accountId")]
    public string? AccountId { get; set; }

    [JsonPropertyName("updatedAt")]
    public double? UpdatedAt { get; set; }

    [JsonPropertyName("link")]
    public ProjectLink? Link { get; set; }

    public string DisplayName => CloudflareProjectIds.TryParse(Id, out var kind, out _)
        ? $"{Name} ({(kind == CloudflareProjectKind.Pages ? "Pages" : "Worker")})"
        : Name;
}

public sealed class ProjectsResponse
{
    [JsonPropertyName("projects")]
    public List<Project> Projects { get; set; } = [];
}

public sealed class WatchedProject
{
    [JsonPropertyName("projectId")]
    public string ProjectId { get; set; } = "";

    [JsonPropertyName("projectName")]
    public string ProjectName { get; set; } = "";

    [JsonPropertyName("teamId")]
    public string TeamId { get; set; } = "";

    /// <summary>Saved entries from before Cloudflare support have no provider and load as Vercel.</summary>
    [JsonPropertyName("provider")]
    [JsonConverter(typeof(JsonStringEnumConverter))]
    public DeploymentProvider Provider { get; set; } = DeploymentProvider.Vercel;

    /// <summary>Vercel IDs keep their original format so saved state stays valid.</summary>
    [JsonIgnore]
    public string Id => Provider == DeploymentProvider.Vercel
        ? $"{TeamId}:{ProjectId}"
        : $"cloudflare:{TeamId}:{ProjectId}";
}
