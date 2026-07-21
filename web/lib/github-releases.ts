export const GITHUB_REPO = process.env.GITHUB_REPO ?? "asitkhanda/toast";

export interface ReleaseAsset {
  name: string;
  download_count: number;
}

export interface GitHubRelease {
  tag_name: string;
  assets: ReleaseAsset[];
}

function githubHeaders(): Record<string, string> {
  const headers: Record<string, string> = {
    Accept: "application/vnd.github+json",
    "User-Agent": "Toast-Web",
    "X-GitHub-Api-Version": "2022-11-28",
  };

  const token = process.env.GITHUB_TOKEN;
  if (token) {
    headers.Authorization = `Bearer ${token}`;
  }

  return headers;
}

export async function fetchAllReleases(): Promise<GitHubRelease[]> {
  const releases: GitHubRelease[] = [];
  let page = 1;

  while (true) {
    const response = await fetch(
      `https://api.github.com/repos/${GITHUB_REPO}/releases?per_page=100&page=${page}`,
      { headers: githubHeaders() },
    );

    if (!response.ok) {
      throw new Error(`GitHub API returned ${response.status}`);
    }

    const batch = (await response.json()) as GitHubRelease[];
    if (batch.length === 0) {
      break;
    }

    releases.push(...batch);
    if (batch.length < 100) {
      break;
    }

    page += 1;
  }

  return releases;
}

export function summarizeReleaseDownloads(releases: GitHubRelease[]) {
  let dmgDownloads = 0;
  let zipDownloads = 0;

  for (const release of releases) {
    for (const asset of release.assets) {
      if (asset.name.endsWith(".dmg")) {
        dmgDownloads += asset.download_count;
      } else if (asset.name.endsWith(".zip")) {
        zipDownloads += asset.download_count;
      }
    }
  }

  return {
    totalDownloads: dmgDownloads + zipDownloads,
    dmgDownloads,
    zipDownloads,
    releaseCount: releases.length,
  };
}
