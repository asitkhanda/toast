using System.Globalization;
using System.Net;
using System.Net.Http.Headers;
using System.Text.Json;
using System.Text.Json.Serialization;
using Toast.Core.Models;

namespace Toast.Core.Services;

public enum CloudflareApiErrorKind
{
    Unauthorized,
    Forbidden,
    NotFound,
    RateLimited,
    ServerError,
    DecodingFailed,
    Network,
    Api,
}

public sealed class CloudflareApiException : Exception
{
    public CloudflareApiException(CloudflareApiErrorKind kind, string message, int? statusCode = null, Exception? inner = null)
        : base(message, inner)
    {
        Kind = kind;
        StatusCode = statusCode;
    }

    public CloudflareApiErrorKind Kind { get; }
    public int? StatusCode { get; }
}

// MARK: Response models

public sealed class CfResultInfo
{
    [JsonPropertyName("page")] public int? Page { get; set; }
    [JsonPropertyName("per_page")] public int? PerPage { get; set; }
    [JsonPropertyName("total_count")] public int? TotalCount { get; set; }
    [JsonPropertyName("total_pages")] public int? TotalPages { get; set; }
}

public sealed class CfMessage
{
    [JsonPropertyName("message")] public string? Message { get; set; }
}

public sealed class CfEnvelope<T>
{
    [JsonPropertyName("success")] public bool? Success { get; set; }
    [JsonPropertyName("result")] public T? Result { get; set; }
    [JsonPropertyName("errors")] public List<CfMessage>? Errors { get; set; }
    [JsonPropertyName("result_info")] public CfResultInfo? ResultInfo { get; set; }
}

public sealed class CfAccount
{
    [JsonPropertyName("id")] public string Id { get; set; } = "";
    [JsonPropertyName("name")] public string? Name { get; set; }
}

public sealed class CfPagesProject
{
    [JsonPropertyName("name")] public string Name { get; set; } = "";
}

public sealed class CfStage
{
    [JsonPropertyName("name")] public string? Name { get; set; }
    [JsonPropertyName("status")] public string? Status { get; set; }
    [JsonPropertyName("started_on")] public string? StartedOn { get; set; }
    [JsonPropertyName("ended_on")] public string? EndedOn { get; set; }
}

public sealed class CfTriggerMetadata
{
    [JsonPropertyName("branch")] public string? Branch { get; set; }
    [JsonPropertyName("commit_hash")] public string? CommitHash { get; set; }
    [JsonPropertyName("commit_message")] public string? CommitMessage { get; set; }
    [JsonPropertyName("author")] public string? Author { get; set; }
}

public sealed class CfTrigger
{
    [JsonPropertyName("metadata")] public CfTriggerMetadata? Metadata { get; set; }
}

public sealed class CfPagesDeployment
{
    [JsonPropertyName("id")] public string Id { get; set; } = "";
    [JsonPropertyName("url")] public string? Url { get; set; }
    [JsonPropertyName("environment")] public string? Environment { get; set; }
    [JsonPropertyName("created_on")] public string? CreatedOn { get; set; }
    [JsonPropertyName("project_name")] public string? ProjectName { get; set; }
    [JsonPropertyName("latest_stage")] public CfStage? LatestStage { get; set; }
    [JsonPropertyName("stages")] public List<CfStage>? Stages { get; set; }
    [JsonPropertyName("deployment_trigger")] public CfTrigger? DeploymentTrigger { get; set; }

    /// <summary>Maps Cloudflare's build stages onto Toast's shared deployment states.</summary>
    public DeploymentState State
    {
        get
        {
            var stages = Stages ?? [];
            if (stages.Any(s => s.Status == "failure") || LatestStage?.Status == "failure")
            {
                return DeploymentState.Error;
            }

            if (stages.Any(s => s.Status == "canceled") || LatestStage?.Status == "canceled")
            {
                return DeploymentState.Canceled;
            }

            return (LatestStage?.Name, LatestStage?.Status) switch
            {
                (null, _) => DeploymentState.Queued,
                ("deploy", "success") => DeploymentState.Ready,
                ("queued", _) => DeploymentState.Queued,
                ("initialize", _) or ("clone_repo", _) => DeploymentState.Initializing,
                ("build", _) or ("deploy", _) => DeploymentState.Building,
                _ => DeploymentState.Queued,
            };
        }
    }

    public Deployment ToDeployment(string fallbackName)
    {
        var state = State;
        var build = Stages?.FirstOrDefault(s => s.Name == "build");
        var deploy = Stages?.FirstOrDefault(s => s.Name == "deploy");
        var finished = state == DeploymentState.Ready ? deploy?.EndedOn ?? LatestStage?.EndedOn : null;

        return new Deployment
        {
            Uid = Id,
            Name = ProjectName ?? fallbackName,
            Url = Url,
            StateRaw = CloudflareApiClient.StateName(state),
            Target = Environment,
            CreatedAt = CloudflareApiClient.Milliseconds(CreatedOn),
            BuildingAt = CloudflareApiClient.Milliseconds(build?.StartedOn),
            Ready = CloudflareApiClient.Milliseconds(finished),
            Meta = new DeploymentMeta
            {
                GithubCommitMessage = DeploymentTrigger?.Metadata?.CommitMessage,
                GithubCommitRef = DeploymentTrigger?.Metadata?.Branch,
                GithubCommitSha = DeploymentTrigger?.Metadata?.CommitHash,
            },
        };
    }
}

public sealed class CfWorkerScript
{
    [JsonPropertyName("id")] public string Id { get; set; } = "";

    /// <summary>Immutable script ID that the Workers Builds API is keyed by.</summary>
    [JsonPropertyName("tag")] public string? Tag { get; set; }
}

public sealed class CfWorkerDeployment
{
    [JsonPropertyName("id")] public string Id { get; set; } = "";
    [JsonPropertyName("created_on")] public string? CreatedOn { get; set; }
    [JsonPropertyName("annotations")] public Dictionary<string, string>? Annotations { get; set; }

    public Deployment ToDeployment(string workerName)
    {
        var created = CloudflareApiClient.Milliseconds(CreatedOn);
        return new Deployment
        {
            Uid = Id,
            Name = workerName,
            StateRaw = "READY",
            Target = "production",
            CreatedAt = created,
            Ready = created,
            Meta = new DeploymentMeta
            {
                GithubCommitMessage = Annotations is not null && Annotations.TryGetValue("workers/message", out var m) ? m : null,
            },
        };
    }
}

public sealed class CfWorkerDeployments
{
    [JsonPropertyName("deployments")] public List<CfWorkerDeployment> Deployments { get; set; } = [];
}

/// <summary>One Workers Builds (Git-connected CI) run. Environment variables in the response are deliberately not read.</summary>
public sealed class CfWorkerBuild
{
    [JsonPropertyName("build_uuid")] public string BuildUuid { get; set; } = "";
    [JsonPropertyName("status")] public string? Status { get; set; }
    [JsonPropertyName("build_outcome")] public string? BuildOutcome { get; set; }
    [JsonPropertyName("created_on")] public string? CreatedOn { get; set; }
    [JsonPropertyName("running_on")] public string? RunningOn { get; set; }
    [JsonPropertyName("stopped_on")] public string? StoppedOn { get; set; }
    [JsonPropertyName("build_trigger_metadata")] public CfTriggerMetadata? Metadata { get; set; }

    public DeploymentState State
    {
        get
        {
            var outcome = BuildOutcome?.ToLowerInvariant();
            switch (Status?.ToLowerInvariant())
            {
                case "stopped" or "finished" or "complete" or "completed":
                    return outcome switch
                    {
                        "success" or "succeeded" => DeploymentState.Ready,
                        "canceled" or "cancelled" => DeploymentState.Canceled,
                        null => DeploymentState.Building,
                        _ => DeploymentState.Error,
                    };
                case "queued" or "pending":
                    return DeploymentState.Queued;
                case "initializing":
                    return DeploymentState.Initializing;
                default:
                    return DeploymentState.Building;
            }
        }
    }

    public Deployment ToDeployment(string workerName)
    {
        var state = State;
        var firstLine = Metadata?.CommitMessage?
            .Split('\n', StringSplitOptions.RemoveEmptyEntries)
            .FirstOrDefault()?.Trim();
        return new Deployment
        {
            Uid = BuildUuid,
            Name = workerName,
            StateRaw = CloudflareApiClient.StateName(state),
            CreatedAt = CloudflareApiClient.Milliseconds(CreatedOn),
            BuildingAt = CloudflareApiClient.Milliseconds(RunningOn),
            Ready = state.IsTerminal() ? CloudflareApiClient.Milliseconds(StoppedOn) : null,
            Meta = new DeploymentMeta
            {
                GithubCommitMessage = string.IsNullOrEmpty(firstLine) ? null : firstLine,
                GithubCommitRef = string.IsNullOrEmpty(Metadata?.Branch) ? null : Metadata!.Branch,
                GithubCommitSha = string.IsNullOrEmpty(Metadata?.CommitHash) ? null : Metadata!.CommitHash,
                GithubCommitAuthorName = Metadata?.Author,
            },
        };
    }
}

public sealed class CloudflareProjectListing
{
    public required IReadOnlyList<Project> Projects { get; init; }
    public string? Notice { get; init; }
}

public sealed class CloudflareApiClient
{
    public const string ReadOnlyRecommendation =
        "This token can do more than Toast needs. For best security, limit it to Cloudflare Pages: Read, "
        + "Workers Scripts: Read and Account Settings: Read.";

    private static readonly JsonSerializerOptions JsonOptions = new() { PropertyNameCaseInsensitive = true };

    private readonly HttpClient _http;
    private readonly string _token;

    public CloudflareApiClient(string token, HttpClient? httpClient = null)
    {
        _token = token;
        _http = httpClient ?? new HttpClient
        {
            BaseAddress = new Uri("https://api.cloudflare.com/client/v4/"),
            Timeout = TimeSpan.FromSeconds(30),
        };
    }

    /// <summary>Pulls the bare token out of common copy-paste mistakes (a "Bearer " prefix, quotes, spaces).</summary>
    public static string SanitizeToken(string raw)
    {
        var token = raw.Trim();
        if (token.StartsWith("bearer ", StringComparison.OrdinalIgnoreCase))
        {
            token = token[7..];
        }

        return token.Trim('"', '\'', '`', ' ', '\t', '\r', '\n');
    }

    public static string StateName(DeploymentState state) => state.ToString().ToUpperInvariant();

    public static double? Milliseconds(string? iso8601) =>
        DateTimeOffset.TryParse(iso8601, CultureInfo.InvariantCulture, DateTimeStyles.AssumeUniversal, out var date)
            ? date.ToUnixTimeMilliseconds()
            : null;

    public async Task<IReadOnlyList<Team>> ListAccountsAsync(CancellationToken ct = default)
    {
        var accounts = new List<CfAccount>();
        for (var page = 1; page <= 20; page++)
        {
            var batch = await GetPageAsync<CfAccount>("accounts", page, ct);
            accounts.AddRange(batch.Items);
            if (batch.Items.Count == 0 || !batch.HasMore)
            {
                break;
            }
        }

        return accounts.Select(a => new Team { Id = a.Id, Name = a.Name }).ToList();
    }

    public async Task<IReadOnlyList<Project>> ListProjectsAsync(string accountId, CancellationToken ct = default) =>
        (await ListProjectsWithNoticeAsync(accountId, ct)).Projects;

    /// <summary>Lists Pages projects and Workers. A token may only cover one, so one being forbidden is tolerated.</summary>
    public async Task<CloudflareProjectListing> ListProjectsWithNoticeAsync(string accountId, CancellationToken ct = default)
    {
        var projects = new List<Project>();
        var failures = new List<Exception>();
        var notes = new List<string>();

        try
        {
            var pages = await ListPagesProjectsAsync(accountId, ct);
            projects.AddRange(pages);
            notes.Add($"Pages: {pages.Count} found");
        }
        catch (Exception ex) when (ex is not OperationCanceledException)
        {
            failures.Add(ex);
            notes.Add($"Pages: {Reason(ex)}");
        }

        try
        {
            var workers = await ListWorkersAsync(accountId, ct);
            projects.AddRange(workers);
            notes.Add($"Workers: {workers.Count} found");
        }
        catch (Exception ex) when (ex is not OperationCanceledException)
        {
            failures.Add(ex);
            notes.Add($"Workers: {Reason(ex)}");
        }

        if (failures.Count == 2)
        {
            throw failures[0];
        }

        return new CloudflareProjectListing
        {
            Projects = projects.OrderBy(p => p.Name, StringComparer.OrdinalIgnoreCase).ToList(),
            Notice = string.Join(" · ", notes),
        };
    }

    private static string Reason(Exception ex) =>
        ex is CloudflareApiException { Kind: CloudflareApiErrorKind.Forbidden } ? "token lacks permission" : ex.Message;

    private async Task<List<Project>> ListPagesProjectsAsync(string accountId, CancellationToken ct)
    {
        var projects = new List<Project>();
        for (var page = 1; page <= 20; page++)
        {
            var batch = await GetPageAsync<CfPagesProject>($"accounts/{accountId}/pages/projects", page, ct);
            projects.AddRange(batch.Items.Select(p => new Project
            {
                Id = CloudflareProjectIds.Make(CloudflareProjectKind.Pages, p.Name),
                Name = p.Name,
                AccountId = accountId,
            }));
            if (batch.Items.Count == 0 || !batch.HasMore)
            {
                break;
            }
        }

        return projects;
    }

    private async Task<List<Project>> ListWorkersAsync(string accountId, CancellationToken ct)
    {
        var scripts = await GetAsync<List<CfWorkerScript>>($"accounts/{accountId}/workers/scripts", ct);
        return scripts.Select(s => new Project
        {
            Id = CloudflareProjectIds.Make(CloudflareProjectKind.Worker, s.Id),
            Name = s.Id,
            AccountId = accountId,
        }).ToList();
    }

    /// <summary>Maps each Worker name to its immutable script tag.</summary>
    public async Task<Dictionary<string, string>> ListWorkerTagsAsync(string accountId, CancellationToken ct = default)
    {
        var scripts = await GetAsync<List<CfWorkerScript>>($"accounts/{accountId}/workers/scripts", ct);
        var tags = new Dictionary<string, string>();
        foreach (var script in scripts)
        {
            if (!string.IsNullOrEmpty(script.Tag))
            {
                tags.TryAdd(script.Id, script.Tag);
            }
        }

        return tags;
    }

    /// <summary>
    /// Latest deployment for a project ID of the form <c>pages:name</c> or <c>worker:name</c>.
    /// For Workers, <paramref name="workerTag"/> enables real build status.
    /// </summary>
    public async Task<Deployment?> LatestDeploymentAsync(
        string accountId,
        string projectId,
        string? workerTag = null,
        CancellationToken ct = default)
    {
        var known = CloudflareProjectIds.TryParse(projectId, out var kind, out var name);
        var encoded = Uri.EscapeDataString(name);

        if (!known || kind == CloudflareProjectKind.Pages)
        {
            var deployments = await GetAsync<List<CfPagesDeployment>>(
                $"accounts/{accountId}/pages/projects/{encoded}/deployments", ct);
            var newest = deployments
                .OrderByDescending(d => Milliseconds(d.CreatedOn) ?? 0)
                .FirstOrDefault();
            return newest?.ToDeployment(name);
        }

        // Prefer Workers Builds (real queued/building/failed/success). Fall back to the
        // deployments list when the token can't read builds or the Worker has none.
        if (workerTag is not null)
        {
            var build = await LatestBuildAsync(accountId, workerTag, ct);
            if (build is not null)
            {
                return build.ToDeployment(name);
            }
        }

        var result = await GetAsync<CfWorkerDeployments>(
            $"accounts/{accountId}/workers/scripts/{encoded}/deployments", ct);
        // The API lists the deployment currently serving traffic first.
        return result.Deployments.FirstOrDefault()?.ToDeployment(name);
    }

    private async Task<CfWorkerBuild?> LatestBuildAsync(string accountId, string workerTag, CancellationToken ct)
    {
        try
        {
            var builds = await GetAsync<List<CfWorkerBuild>>(
                $"accounts/{accountId}/builds/workers/{workerTag}/builds", ct);
            return builds.OrderByDescending(b => Milliseconds(b.CreatedOn) ?? 0).FirstOrDefault();
        }
        catch (CloudflareApiException ex) when (
            ex.Kind is CloudflareApiErrorKind.Forbidden or CloudflareApiErrorKind.NotFound or CloudflareApiErrorKind.Api)
        {
            return null;
        }
    }

    public async Task<TokenValidation> ValidateTokenAsync(CancellationToken ct = default)
    {
        var accounts = await ListAccountsAsync(ct);
        if (accounts.Count == 0)
        {
            throw new CloudflareApiException(CloudflareApiErrorKind.Api, "This token can't see any Cloudflare accounts.");
        }

        _ = await ListProjectsAsync(accounts[0].Id, ct);
        var elevated = await RequestSucceededAsync($"accounts/{accounts[0].Id}/tokens", ct);
        return new TokenValidation { ScopeWarning = elevated ? ReadOnlyRecommendation : null };
    }

    private async Task<bool> RequestSucceededAsync(string path, CancellationToken ct)
    {
        try
        {
            using var request = NewRequest(path);
            using var response = await _http.SendAsync(request, ct);
            return response.IsSuccessStatusCode;
        }
        catch (OperationCanceledException)
        {
            throw;
        }
        catch
        {
            return false;
        }
    }

    // MARK: Networking

    private sealed class Page<T>
    {
        public required List<T> Items { get; init; }
        public CfResultInfo? Info { get; init; }

        public bool HasMore
        {
            get
            {
                if (Info?.Page is not { } page)
                {
                    return false;
                }

                if (Info.TotalPages is { } totalPages)
                {
                    return page < totalPages;
                }

                return Info.TotalCount is { } total && Info.PerPage is { } perPage && perPage > 0
                    && page * perPage < total;
            }
        }
    }

    /// <summary>Fetches one page without sending per_page, because some endpoints reject the sizes we would pick.</summary>
    private async Task<Page<T>> GetPageAsync<T>(string path, int page, CancellationToken ct)
    {
        var envelope = await SendAsync<List<T>>(page > 1 ? $"{path}?page={page}" : path, ct);
        return new Page<T> { Items = envelope.Result ?? [], Info = envelope.ResultInfo };
    }

    private async Task<T> GetAsync<T>(string path, CancellationToken ct)
    {
        var envelope = await SendAsync<T>(path, ct);
        return envelope.Result
            ?? throw new CloudflareApiException(
                CloudflareApiErrorKind.Api,
                envelope.Errors?.FirstOrDefault()?.Message ?? "Cloudflare returned no data.");
    }

    private HttpRequestMessage NewRequest(string path)
    {
        var request = new HttpRequestMessage(HttpMethod.Get, path);
        request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", _token);
        request.Headers.Accept.Add(new MediaTypeWithQualityHeaderValue("application/json"));
        return request;
    }

    private async Task<CfEnvelope<T>> SendAsync<T>(string path, CancellationToken ct)
    {
        for (var attempt = 0; ; attempt++)
        {
            try
            {
                using var request = NewRequest(path);
                using var response = await _http.SendAsync(request, ct);
                var body = await response.Content.ReadAsStringAsync(ct);

                if (!response.IsSuccessStatusCode)
                {
                    throw MapStatus(response.StatusCode, body);
                }

                try
                {
                    var envelope = JsonSerializer.Deserialize<CfEnvelope<T>>(body, JsonOptions)
                        ?? throw new CloudflareApiException(CloudflareApiErrorKind.DecodingFailed, "Unexpected response from Cloudflare.");
                    if (envelope.Success == false)
                    {
                        throw new CloudflareApiException(
                            CloudflareApiErrorKind.Api,
                            envelope.Errors?.FirstOrDefault()?.Message ?? "Cloudflare request failed.");
                    }

                    return envelope;
                }
                catch (JsonException ex)
                {
                    throw new CloudflareApiException(CloudflareApiErrorKind.DecodingFailed, "Unexpected response from Cloudflare.", inner: ex);
                }
            }
            catch (OperationCanceledException)
            {
                throw;
            }
            catch (CloudflareApiException ex) when (IsRetryable(ex) && attempt < 2)
            {
                await Task.Delay(TimeSpan.FromMilliseconds(attempt == 0 ? 500 : 1500), ct);
            }
            catch (CloudflareApiException)
            {
                throw;
            }
            catch (Exception) when (attempt < 2)
            {
                await Task.Delay(TimeSpan.FromMilliseconds(attempt == 0 ? 500 : 1500), ct);
            }
            catch (Exception ex)
            {
                throw new CloudflareApiException(CloudflareApiErrorKind.Network, ex.Message, inner: ex);
            }
        }
    }

    private static bool IsRetryable(CloudflareApiException error) =>
        error.Kind is CloudflareApiErrorKind.RateLimited or CloudflareApiErrorKind.ServerError or CloudflareApiErrorKind.Network;

    private static CloudflareApiException MapStatus(HttpStatusCode status, string body)
    {
        switch (status)
        {
            case HttpStatusCode.Unauthorized:
                return new CloudflareApiException(
                    CloudflareApiErrorKind.Unauthorized,
                    "Cloudflare didn't accept this token. Create a new token and replace it in Settings.",
                    401);
            case HttpStatusCode.Forbidden:
                return new CloudflareApiException(
                    CloudflareApiErrorKind.Forbidden,
                    "This Cloudflare token is missing a permission. It needs Account Settings: Read plus Cloudflare Pages: Read and/or Workers Scripts: Read.",
                    403);
            case HttpStatusCode.NotFound:
                return new CloudflareApiException(CloudflareApiErrorKind.NotFound, "Cloudflare couldn't find that.", 404);
            case HttpStatusCode.TooManyRequests:
                return new CloudflareApiException(
                    CloudflareApiErrorKind.RateLimited,
                    "Cloudflare asked Toast to slow down. It will try again in a minute.",
                    429);
            case HttpStatusCode.BadRequest:
                return new CloudflareApiException(CloudflareApiErrorKind.Api, BadRequestMessage(body), 400);
            default:
                return new CloudflareApiException(
                    CloudflareApiErrorKind.ServerError,
                    $"Cloudflare is having trouble ({(int)status}). Toast will keep trying.",
                    (int)status);
        }
    }

    private static string BadRequestMessage(string body)
    {
        string? detail = null;
        try
        {
            detail = JsonSerializer.Deserialize<CfEnvelope<JsonElement>>(body, JsonOptions)?.Errors?.FirstOrDefault()?.Message;
        }
        catch (JsonException)
        {
        }

        if (detail?.Contains("Authorization header", StringComparison.OrdinalIgnoreCase) == true)
        {
            return "That doesn't look like a Cloudflare token. Paste only the token itself (about 40 letters, numbers, - and _), "
                + "without \"Bearer\", quotes, or the rest of a command.";
        }

        return detail is null ? "Cloudflare rejected the request (400)." : $"Cloudflare rejected the request: {detail}";
    }
}
