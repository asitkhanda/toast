using System.Net;
using System.Net.Http.Headers;
using System.Text.Json;
using Toast.Core.Models;

namespace Toast.Core.Services;

public enum VercelApiErrorKind
{
    Unauthorized,
    Forbidden,
    NotFound,
    RateLimited,
    ServerError,
    DecodingFailed,
    Network,
    InvalidUrl,
}

public sealed class VercelApiException : Exception
{
    public VercelApiException(VercelApiErrorKind kind, string message, int? statusCode = null, Exception? inner = null)
        : base(message, inner)
    {
        Kind = kind;
        StatusCode = statusCode;
    }

    public VercelApiErrorKind Kind { get; }
    public int? StatusCode { get; }
}

public sealed class TokenValidation
{
    public const string ReadOnlyRecommendation =
        "For best security, create a Vercel token with read-only access scoped to the teams you need.";

    public string? ScopeWarning { get; init; }
}

public sealed class VercelApiClient
{
    private static readonly JsonSerializerOptions JsonOptions = new()
    {
        PropertyNameCaseInsensitive = true,
    };

    private readonly HttpClient _http;
    private readonly string _token;

    public VercelApiClient(string token, HttpClient? httpClient = null)
    {
        _token = token;
        _http = httpClient ?? new HttpClient
        {
            BaseAddress = new Uri("https://api.vercel.com"),
            Timeout = TimeSpan.FromSeconds(30),
        };
        if (_http.DefaultRequestHeaders.Authorization is null)
        {
            _http.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Bearer", _token);
            _http.DefaultRequestHeaders.Accept.Add(new MediaTypeWithQualityHeaderValue("application/json"));
        }
    }

    public async Task<IReadOnlyList<Team>> ListTeamsAsync(CancellationToken ct = default)
    {
        var response = await GetAsync<TeamsResponse>("/v2/teams", ct);
        return response.Teams;
    }

    public async Task<IReadOnlyList<Project>> ListProjectsAsync(string teamId, CancellationToken ct = default)
    {
        var response = await GetAsync<ProjectsResponse>(
            $"/v9/projects?teamId={Uri.EscapeDataString(teamId)}&limit=100",
            ct);
        return response.Projects;
    }

    public async Task<IReadOnlyList<Deployment>> ListDeploymentsAsync(
        string projectId,
        string teamId,
        int limit = 5,
        CancellationToken ct = default)
    {
        var response = await GetAsync<DeploymentsResponse>(
            $"/v7/deployments?projectId={Uri.EscapeDataString(projectId)}&teamId={Uri.EscapeDataString(teamId)}&limit={limit}",
            ct);
        return response.Deployments;
    }

    public async Task<TokenValidation> ValidateTokenAsync(CancellationToken ct = default)
    {
        _ = await ListTeamsAsync(ct);
        var elevated = await HasElevatedAccountAccessAsync(ct);
        return new TokenValidation
        {
            ScopeWarning = elevated ? TokenValidation.ReadOnlyRecommendation : null,
        };
    }

    private async Task<bool> HasElevatedAccountAccessAsync(CancellationToken ct)
    {
        try
        {
            using var request = new HttpRequestMessage(HttpMethod.Get, "/v3/user/tokens?limit=1");
            request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", _token);
            using var response = await _http.SendAsync(request, ct);
            return response.IsSuccessStatusCode;
        }
        catch
        {
            return false;
        }
    }

    private async Task<T> GetAsync<T>(string path, CancellationToken ct)
    {
        try
        {
            using var request = new HttpRequestMessage(HttpMethod.Get, path);
            request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", _token);
            using var response = await _http.SendAsync(request, ct);
            var body = await response.Content.ReadAsStringAsync(ct);

            if (!response.IsSuccessStatusCode)
            {
                throw MapStatus(response.StatusCode);
            }

            try
            {
                return JsonSerializer.Deserialize<T>(body, JsonOptions)
                    ?? throw new VercelApiException(VercelApiErrorKind.DecodingFailed, "Unexpected response from Vercel.");
            }
            catch (JsonException ex)
            {
                throw new VercelApiException(VercelApiErrorKind.DecodingFailed, "Unexpected response from Vercel.", inner: ex);
            }
        }
        catch (VercelApiException)
        {
            throw;
        }
        catch (Exception ex)
        {
            throw new VercelApiException(VercelApiErrorKind.Network, ex.Message, inner: ex);
        }
    }

    private static VercelApiException MapStatus(HttpStatusCode status) => status switch
    {
        HttpStatusCode.Unauthorized => new VercelApiException(
            VercelApiErrorKind.Unauthorized,
            "Invalid or expired Vercel token. Reconnect in Settings.",
            401),
        HttpStatusCode.Forbidden => new VercelApiException(
            VercelApiErrorKind.Forbidden,
            "You don't have permission to access this resource.",
            403),
        HttpStatusCode.NotFound => new VercelApiException(
            VercelApiErrorKind.NotFound,
            "Resource not found.",
            404),
        HttpStatusCode.TooManyRequests => new VercelApiException(
            VercelApiErrorKind.RateLimited,
            "Vercel rate limit reached. Will retry shortly.",
            429),
        _ => new VercelApiException(
            VercelApiErrorKind.ServerError,
            $"Vercel server error ({(int)status}).",
            (int)status),
    };
}
