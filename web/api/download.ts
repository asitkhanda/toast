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

export default async function handler(): Promise<Response> {
  const response = await fetch(
    `https://api.github.com/repos/${GITHUB_REPO}/releases/latest`,
    {
      headers: {
        Accept: "application/vnd.github+json",
        "User-Agent": "Vercel-Status-Download",
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

  return new Response(null, {
    status: 302,
    headers: {
      Location: dmg.browser_download_url,
      "Cache-Control": "public, max-age=300",
    },
  });
}
