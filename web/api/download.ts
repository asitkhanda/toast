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

export default async function handler(): Promise<Response> {
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
  const dmg = release.assets.find((asset) => asset.name.endsWith(".dmg"));

  if (!dmg) {
    return new Response("No DMG found for latest release.", { status: 404 });
  }

  const checksumsAsset = release.assets.find(
    (asset) => asset.name === "SHA256SUMS.txt",
  );

  let checksum: string | undefined;
  if (checksumsAsset) {
    const checksumsResponse = await fetch(checksumsAsset.browser_download_url, {
      headers: { "User-Agent": "Toast-Download" },
    });
    if (checksumsResponse.ok) {
      checksum = parseChecksum(await checksumsResponse.text(), dmg.name);
    }
  }

  const headers: Record<string, string> = {
    Location: dmg.browser_download_url,
    "Cache-Control": "public, max-age=300",
  };

  if (checksum) {
    headers["X-Toast-SHA256"] = checksum;
    headers["X-Toast-Verify"] =
      "Compare with SHA256SUMS.txt on the GitHub release before opening the DMG.";
  }

  return new Response(null, {
    status: 302,
    headers,
  });
}
