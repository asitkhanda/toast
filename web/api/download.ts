export const config = {
  runtime: "edge",
};

const GITHUB_REPO = process.env.GITHUB_REPO ?? "asitkhanda/toast";

interface ReleaseAsset {
  name: string;
  browser_download_url: string;
}

interface GitHubRelease {
  assets: ReleaseAsset[];
}

type Platform = "mac" | "windows";

function parseChecksum(manifest: string, fileName: string): string | undefined {
  for (const line of manifest.split("\n")) {
    const trimmed = line.trim();
    if (!trimmed || !trimmed.includes(fileName)) {
      continue;
    }
    const [checksum] = trimmed.split(/\s+/);
    if (checksum?.length === 64) {
      return checksum;
    }
  }
  return undefined;
}

function resolvePlatform(request: Request): Platform {
  const url = new URL(request.url);
  const explicit = url.searchParams.get("platform")?.toLowerCase();
  if (explicit === "mac" || explicit === "macos" || explicit === "darwin") {
    return "mac";
  }
  if (explicit === "windows" || explicit === "win") {
    return "windows";
  }

  const ua = request.headers.get("user-agent") ?? "";
  if (/windows/i.test(ua)) {
    return "windows";
  }
  return "mac";
}

function findAsset(
  assets: ReleaseAsset[],
  platform: Platform,
): ReleaseAsset | undefined {
  if (platform === "windows") {
    return (
      assets.find((asset) => asset.name.endsWith("-win-x64-Setup.exe")) ??
      assets.find((asset) => /win.*Setup\.exe$/i.test(asset.name))
    );
  }
  return assets.find((asset) => asset.name.endsWith(".dmg"));
}

export default async function handler(request: Request): Promise<Response> {
  const preferred = resolvePlatform(request);

  const response = await fetch(
    `https://api.github.com/repos/${GITHUB_REPO}/releases/latest`,
    {
      headers: {
        Accept: "application/vnd.github+json",
        "User-Agent": "Toast-Download",
        "X-GitHub-Api-Version": "2022-11-28",
      },
    },
  );

  if (!response.ok) {
    return new Response("Could not resolve latest release.", { status: 502 });
  }

  const release = (await response.json()) as GitHubRelease;
  const fallback: Platform = preferred === "mac" ? "windows" : "mac";
  const asset =
    findAsset(release.assets, preferred) ?? findAsset(release.assets, fallback);

  if (!asset) {
    return new Response("No download found for latest release.", {
      status: 404,
    });
  }

  const checksumsAsset = release.assets.find(
    (candidate) => candidate.name === "SHA256SUMS.txt",
  );

  let checksum: string | undefined;
  if (checksumsAsset) {
    const checksumsResponse = await fetch(checksumsAsset.browser_download_url, {
      headers: { "User-Agent": "Toast-Download" },
    });
    if (checksumsResponse.ok) {
      checksum = parseChecksum(await checksumsResponse.text(), asset.name);
    }
  }

  const headers: Record<string, string> = {
    Location: asset.browser_download_url,
    "Cache-Control": "public, max-age=300",
    "X-Toast-Platform": asset.name.includes("win") ? "windows" : "mac",
  };

  if (checksum) {
    headers["X-Toast-SHA256"] = checksum;
    headers["X-Toast-Verify"] =
      "Compare with SHA256SUMS.txt on the GitHub release before installing.";
  }

  return new Response(null, {
    status: 302,
    headers,
  });
}
