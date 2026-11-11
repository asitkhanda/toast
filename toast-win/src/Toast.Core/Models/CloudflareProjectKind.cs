namespace Toast.Core.Models;

/// <summary>
/// Cloudflare projects are Pages sites or Workers. The kind is stored in the project ID
/// (<c>pages:name</c> or <c>worker:name</c>) so both share one watched-project list.
/// </summary>
public enum CloudflareProjectKind
{
    Pages,
    Worker,
}

public static class CloudflareProjectIds
{
    public static string Make(CloudflareProjectKind kind, string name) =>
        $"{(kind == CloudflareProjectKind.Pages ? "pages" : "worker")}:{name}";

    public static bool TryParse(string projectId, out CloudflareProjectKind kind, out string name)
    {
        kind = CloudflareProjectKind.Pages;
        name = projectId;
        var index = projectId.IndexOf(':');
        if (index <= 0)
        {
            return false;
        }

        switch (projectId[..index])
        {
            case "pages":
                kind = CloudflareProjectKind.Pages;
                break;
            case "worker":
                kind = CloudflareProjectKind.Worker;
                break;
            default:
                return false;
        }

        name = projectId[(index + 1)..];
        return true;
    }

    public static string NameOf(string projectId) =>
        TryParse(projectId, out _, out var name) ? name : projectId;
}
