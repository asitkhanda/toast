using System.Net;
using System.Text;
using System.Text.Json;
using Toast.Core.Models;
using Toast.Core.Services;

namespace Toast.Core.Tests;

public sealed class CloudflareTests
{
    private sealed class StubHandler : HttpMessageHandler
    {
        private readonly Dictionary<string, (HttpStatusCode Status, string Body)> _responses;

        public StubHandler(Dictionary<string, (HttpStatusCode, string)> responses) => _responses = responses;

        protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken cancellationToken)
        {
            var path = request.RequestUri!.AbsolutePath;
            var (status, body) = _responses.TryGetValue(path, out var found) ? found : (HttpStatusCode.NotFound, "{}");
            return Task.FromResult(new HttpResponseMessage(status)
            {
                Content = new StringContent(body, Encoding.UTF8, "application/json"),
            });
        }
    }

    private static CloudflareApiClient Client(Dictionary<string, (HttpStatusCode, string)> responses) =>
        new("token", new HttpClient(new StubHandler(responses))
        {
            BaseAddress = new Uri("https://api.cloudflare.com/client/v4/"),
        });

    private static CfPagesDeployment Pages(string json) =>
        JsonSerializer.Deserialize<CfPagesDeployment>(json)!;

    private static CfWorkerBuild Build(string status, string? outcome) =>
        JsonSerializer.Deserialize<CfWorkerBuild>(
            $"{{\"build_uuid\":\"b1\",\"status\":\"{status}\",\"build_outcome\":{(outcome is null ? "null" : $"\"{outcome}\"")},"
            + "\"created_on\":\"2026-11-10T09:18:00.738Z\",\"running_on\":\"2026-11-10T09:18:02.985Z\","
            + "\"stopped_on\":\"2026-11-10T09:18:34.887Z\","
            + "\"build_trigger_metadata\":{\"branch\":\"main\",\"commit_hash\":\"0243f324f6e38d1a\","
            + "\"commit_message\":\"Frosted glass\\n\\nCo-Authored-By: x\",\"author\":\"A\","
            + "\"environment_variables\":{\"SECRET\":{\"is_secret\":true,\"value\":null}}}}")!;

    [Fact]
    public void SuccessfulPagesDeployIsReady()
    {
        var deployment = Pages("""
            {"id":"d1","url":"https://abc.my-site.pages.dev","environment":"production",
             "created_on":"2026-11-11T10:00:00.123Z","project_name":"my-site",
             "latest_stage":{"name":"deploy","status":"success","ended_on":"2026-11-11T10:02:00Z"},
             "stages":[
               {"name":"build","status":"success","started_on":"2026-11-11T10:00:30Z","ended_on":"2026-11-11T10:01:00Z"},
               {"name":"deploy","status":"success","started_on":"2026-11-11T10:01:00Z","ended_on":"2026-11-11T10:02:00Z"}],
             "deployment_trigger":{"metadata":{"branch":"main","commit_hash":"abcdef123456","commit_message":"Ship it"}}}
            """);

        Assert.Equal(DeploymentState.Ready, deployment.State);
        var mapped = deployment.ToDeployment("fallback");
        Assert.Equal(DeploymentState.Ready, mapped.Status);
        Assert.True(mapped.IsProduction);
        Assert.Equal("main", mapped.Branch);
        Assert.Equal("abcdef1", mapped.CommitSha);
        Assert.Equal("Ship it", mapped.CommitMessage);
        Assert.NotNull(mapped.CreatedAt);
        Assert.NotNull(mapped.Ready);
    }

    [Theory]
    [InlineData("queued", "active", DeploymentState.Queued)]
    [InlineData("initialize", "active", DeploymentState.Initializing)]
    [InlineData("clone_repo", "active", DeploymentState.Initializing)]
    [InlineData("build", "active", DeploymentState.Building)]
    [InlineData("deploy", "active", DeploymentState.Building)]
    [InlineData("deploy", "success", DeploymentState.Ready)]
    [InlineData("build", "failure", DeploymentState.Error)]
    [InlineData("build", "canceled", DeploymentState.Canceled)]
    public void PagesStageMapping(string stage, string status, DeploymentState expected)
    {
        var deployment = Pages($"{{\"id\":\"d\",\"latest_stage\":{{\"name\":\"{stage}\",\"status\":\"{status}\"}},\"stages\":[]}}");
        Assert.Equal(expected, deployment.State);
    }

    [Fact]
    public void FailureInAnEarlierStageWins()
    {
        var deployment = Pages("""
            {"id":"d","latest_stage":{"name":"deploy","status":"idle"},
             "stages":[{"name":"build","status":"failure"},{"name":"deploy","status":"idle"}]}
            """);
        Assert.Equal(DeploymentState.Error, deployment.State);
    }

    [Theory]
    [InlineData("queued", null, DeploymentState.Queued)]
    [InlineData("initializing", null, DeploymentState.Initializing)]
    [InlineData("running", null, DeploymentState.Building)]
    [InlineData("stopped", "success", DeploymentState.Ready)]
    [InlineData("stopped", "fail", DeploymentState.Error)]
    [InlineData("stopped", "canceled", DeploymentState.Canceled)]
    public void WorkerBuildStateMapping(string status, string? outcome, DeploymentState expected) =>
        Assert.Equal(expected, Build(status, outcome).State);

    [Fact]
    public void WorkerBuildBecomesDeploymentWithFirstLineOfCommit()
    {
        var deployment = Build("stopped", "success").ToDeployment("asit-work");
        Assert.Equal(DeploymentState.Ready, deployment.Status);
        Assert.Equal("Frosted glass", deployment.CommitMessage);
        Assert.Equal("main", deployment.Branch);
        Assert.Equal("0243f32", deployment.CommitSha);
        Assert.NotNull(deployment.Ready);
    }

    [Fact]
    public void ProjectIdsRoundTrip()
    {
        var pages = CloudflareProjectIds.Make(CloudflareProjectKind.Pages, "my-site");
        var worker = CloudflareProjectIds.Make(CloudflareProjectKind.Worker, "api:v2");
        Assert.True(CloudflareProjectIds.TryParse(pages, out var pagesKind, out _));
        Assert.Equal(CloudflareProjectKind.Pages, pagesKind);
        Assert.True(CloudflareProjectIds.TryParse(worker, out var workerKind, out var name));
        Assert.Equal(CloudflareProjectKind.Worker, workerKind);
        Assert.Equal("api:v2", name);
        Assert.False(CloudflareProjectIds.TryParse("plain-name", out _, out _));
        Assert.Equal("plain-name", CloudflareProjectIds.NameOf("plain-name"));
    }

    [Fact]
    public void LegacyWatchedProjectsLoadAsVercel()
    {
        var legacy = JsonSerializer.Deserialize<WatchedProject>("{\"projectId\":\"prj_1\",\"projectName\":\"web\",\"teamId\":\"team_1\"}")!;
        Assert.Equal(DeploymentProvider.Vercel, legacy.Provider);
        Assert.Equal("team_1:prj_1", legacy.Id);

        var cloudflare = new WatchedProject { ProjectId = "worker:site", ProjectName = "site", TeamId = "acc", Provider = DeploymentProvider.Cloudflare };
        Assert.NotEqual(legacy.Id, cloudflare.Id);

        var roundTrip = JsonSerializer.Deserialize<WatchedProject>(JsonSerializer.Serialize(cloudflare))!;
        Assert.Equal(DeploymentProvider.Cloudflare, roundTrip.Provider);
    }

    [Fact]
    public void TokenSanitizing()
    {
        Assert.Equal("abc123", CloudflareApiClient.SanitizeToken("  abc123\n"));
        Assert.Equal("abc123", CloudflareApiClient.SanitizeToken("Bearer abc123"));
        Assert.Equal("abc123", CloudflareApiClient.SanitizeToken("\"abc123\""));
    }

    [Fact]
    public async Task ListsPagesAndWorkers()
    {
        var client = Client(new()
        {
            ["/client/v4/accounts/acc/pages/projects"] = (HttpStatusCode.OK,
                "{\"result\":[],\"success\":true,\"result_info\":{\"page\":1,\"per_page\":10,\"total_count\":0,\"total_pages\":0}}"),
            ["/client/v4/accounts/acc/workers/scripts"] = (HttpStatusCode.OK,
                "{\"result\":[{\"id\":\"aiswariya\",\"tag\":\"t1\",\"routes\":[{\"pattern\":\"x\"}]},{\"id\":\"asit-work\",\"tag\":\"t2\"}],\"success\":true}"),
        });

        var listing = await client.ListProjectsWithNoticeAsync("acc");
        Assert.Equal(["aiswariya", "asit-work"], listing.Projects.Select(p => p.Name).ToArray());
        Assert.Equal("worker:aiswariya", listing.Projects[0].Id);
        Assert.Equal("Pages: 0 found · Workers: 2 found", listing.Notice);
    }

    [Fact]
    public async Task WorkerUsesNewestBuildWhenReadable()
    {
        var client = Client(new()
        {
            ["/client/v4/accounts/acc/builds/workers/tag1/builds"] = (HttpStatusCode.OK, """
                {"result":[
                  {"build_uuid":"old","status":"stopped","build_outcome":"success","created_on":"2026-11-01T00:00:00Z"},
                  {"build_uuid":"new","status":"running","build_outcome":null,"created_on":"2026-11-10T00:00:00Z"}],
                 "success":true}
                """),
        });

        var deployment = await client.LatestDeploymentAsync("acc", "worker:w", "tag1");
        Assert.Equal("new", deployment?.Uid);
        Assert.Equal(DeploymentState.Building, deployment?.Status);
    }

    [Fact]
    public async Task WorkerFallsBackToDeploymentsWithoutBuildAccess()
    {
        var client = Client(new()
        {
            ["/client/v4/accounts/acc/builds/workers/tag1/builds"] = (HttpStatusCode.Forbidden, "{\"success\":false,\"errors\":[{\"message\":\"forbidden\"}]}"),
            ["/client/v4/accounts/acc/workers/scripts/w/deployments"] = (HttpStatusCode.OK, """
                {"result":{"deployments":[{"id":"d1","created_on":"2026-11-10T10:00:00Z","annotations":{"workers/message":"Manual"}}]},"success":true}
                """),
        });

        var deployment = await client.LatestDeploymentAsync("acc", "worker:w", "tag1");
        Assert.Equal("d1", deployment?.Uid);
        Assert.Equal(DeploymentState.Ready, deployment?.Status);
        Assert.Equal("Manual", deployment?.CommitMessage);
    }

    [Fact]
    public async Task BadTokenFormatGetsAPlainExplanation()
    {
        var client = Client(new()
        {
            ["/client/v4/accounts"] = (HttpStatusCode.BadRequest,
                "{\"success\":false,\"errors\":[{\"message\":\"Invalid format for Authorization header\"}]}"),
        });

        var error = await Assert.ThrowsAsync<CloudflareApiException>(() => client.ListAccountsAsync());
        Assert.Contains("doesn't look like a Cloudflare token", error.Message);
    }
}
