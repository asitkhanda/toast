import {
  fetchAllReleases,
  GITHUB_REPO,
  summarizeReleaseDownloads,
} from "../lib/github-releases";

export const config = {
  runtime: "edge",
};

export default async function handler(): Promise<Response> {
  try {
    const releases = await fetchAllReleases();
    const downloads = summarizeReleaseDownloads(releases);

    return Response.json(
      {
        repo: GITHUB_REPO,
        ...downloads,
      },
      {
        headers: {
          "Cache-Control": "public, max-age=3600, s-maxage=3600",
        },
      },
    );
  } catch {
    return Response.json(
      { error: "Could not load download stats." },
      { status: 502 },
    );
  }
}
