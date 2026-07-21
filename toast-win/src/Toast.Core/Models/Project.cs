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

    public string DisplayName => Name;
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

    [JsonIgnore]
    public string Id => $"{TeamId}:{ProjectId}";
}
