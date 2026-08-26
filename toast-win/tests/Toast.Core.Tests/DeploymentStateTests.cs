using System.Text.Json;
using Toast.Core.Models;

namespace Toast.Core.Tests;

public sealed class DeploymentStateTests
{
    [Theory]
    [InlineData("QUEUED", DeploymentState.Queued)]
    [InlineData("INITIALIZING", DeploymentState.Initializing)]
    [InlineData("BUILDING", DeploymentState.Building)]
    [InlineData("READY", DeploymentState.Ready)]
    [InlineData("ERROR", DeploymentState.Error)]
    [InlineData("CANCELED", DeploymentState.Canceled)]
    [InlineData("CANCELLED", DeploymentState.Canceled)]
    [InlineData("BLOCKED", DeploymentState.Blocked)]
    [InlineData("unknown", DeploymentState.Queued)]
    public void ParseMapsVercelStates(string value, DeploymentState expected) =>
        Assert.Equal(expected, DeploymentStateExtensions.Parse(value));

    [Fact]
    public void DeploymentPrefersReadyStateAndPreservesPresentationHelpers()
    {
        var deployment = new Deployment
        {
            Uid = "dpl_123",
            Name = "web",
            StateRaw = "BUILDING",
            ReadyStateRaw = "READY",
            Url = "preview.example.com",
            Target = "PRODUCTION",
            Meta = new DeploymentMeta
            {
                GithubCommitMessage = "Ship it",
                GithubCommitSha = "123456789",
            },
        };

        Assert.Equal(DeploymentState.Ready, deployment.Status);
        Assert.Equal("Ship it", deployment.CommitMessage);
        Assert.Equal("1234567", deployment.CommitSha);
        Assert.True(deployment.IsProduction);
        Assert.Equal("https://preview.example.com/", deployment.PreviewUrl?.ToString());
    }

    [Fact]
    public void DeploymentStateJsonUsesVercelStringFields()
    {
        var deployment = JsonSerializer.Deserialize<Deployment>(
            "{\"uid\":\"dpl_1\",\"name\":\"web\",\"readyState\":\"ERROR\"}");

        Assert.NotNull(deployment);
        Assert.Equal(DeploymentState.Error, deployment!.Status);
    }
}
