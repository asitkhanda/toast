namespace Toast.Core.Models;

/// <summary>Which service a watched project is deployed on. Vercel must stay 0 so saved data loads as Vercel.</summary>
public enum DeploymentProvider
{
    Vercel = 0,
    Cloudflare = 1,
}

public static class DeploymentProviderExtensions
{
    public static string DisplayName(this DeploymentProvider provider) => provider switch
    {
        DeploymentProvider.Cloudflare => "Cloudflare",
        _ => "Vercel",
    };

    public static string AccountNoun(this DeploymentProvider provider) => provider switch
    {
        DeploymentProvider.Cloudflare => "Account",
        _ => "Team",
    };

    public static string TokenPlaceholder(this DeploymentProvider provider) => provider switch
    {
        DeploymentProvider.Cloudflare => "Cloudflare API token",
        _ => "Vercel token",
    };

    public static string TokensUrl(this DeploymentProvider provider) => provider switch
    {
        DeploymentProvider.Cloudflare => "https://dash.cloudflare.com/profile/api-tokens",
        _ => "https://vercel.com/account/tokens",
    };

    public static string TokenAdvice(this DeploymentProvider provider) => provider switch
    {
        DeploymentProvider.Cloudflare =>
            "Create a custom API token with these permissions, each set to Read: "
            + "Account Settings, Cloudflare Pages, Workers Scripts. "
            + "Optional: Workers Builds Configuration, for live Workers build progress. "
            + "Limit it to the account Toast should watch.",
        _ => "Use a read-only, team-scoped personal access token.",
    };
}
