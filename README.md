# Vercel Status

A macOS menu bar app that shows live Vercel deployment status for your watched projects.

- **Download:** [toast.asit.space/download](https://toast.asit.space/download)
- **Update feed:** [toast.asit.space/appcast.xml](https://toast.asit.space/appcast.xml)
- **Landing page:** [toast.asit.space](https://toast.asit.space)

## Install

1. Download from [toast.asit.space/download](https://toast.asit.space/download) (redirects to the latest `.dmg`).
2. Open the DMG and drag **Vercel Status** into **Applications**.
3. **First launch:** right-click the app and choose **Open** (required because the app is not notarized).
4. Complete onboarding with your [Vercel personal access token](https://vercel.com/account/tokens).

Automatic updates are delivered via [Sparkle](https://sparkle-project.org/) after the first install.

## Build locally

```bash
cd VercelStatus
./build.sh
open "dist/Vercel Status.app"
```

Requires macOS 14+ and Xcode command-line tools.

## Repository layout

```
├── VercelStatus/          # macOS app (Swift + Sparkle)
├── web/                   # Static site + /download redirect (Vercel)
│   ├── api/download.ts    # Edge function → latest .dmg on GitHub Releases
│   └── public/            # Landing page + appcast feed
└── .github/workflows/     # Release automation
```

## Sparkle signing keys (one-time setup)

Before your first release, generate EdDSA keys on your Mac:

```bash
cd VercelStatus
chmod +x scripts/setup-sparkle-keys.sh
./scripts/setup-sparkle-keys.sh
```

Then:

1. The script updates `SUPublicEDKey` in `Resources/Info.plist` automatically.
2. Add the **private key** to GitHub → **Settings → Secrets and variables → Actions** as `SPARKLE_PRIVATE_KEY` (paste contents of `VercelStatus/sparkle-private-key`).

Never commit the private key. The file is listed in `.gitignore`.

## GitHub setup

1. Initialize and push this repo to [github.com/asitkhanda/toast](https://github.com/asitkhanda/toast):

   ```bash
   git init
   git add .
   git commit -m "Initial commit with Sparkle auto-updates"
   git branch -M main
   git remote add origin git@github.com:asitkhanda/toast.git
   git push -u origin main
   ```

2. Add the `SPARKLE_PRIVATE_KEY` secret (see above).

## Vercel setup

1. Import the GitHub repo in [Vercel](https://vercel.com).
2. Set **Root Directory** to `web`.
3. Set **Output Directory** to `public` (Build Command can stay empty).
4. Deploy (static site plus one Edge Function — no build command required).
5. Add custom domain **`toast.asit.space`** in Vercel → Domains.
6. In your DNS provider for `asit.space`, add the CNAME record Vercel shows (typically `toast` → `cname.vercel-dns.com`).
7. Verify [https://toast.asit.space/](https://toast.asit.space/) shows the landing page, [https://toast.asit.space/download](https://toast.asit.space/download) redirects to the latest DMG, and [https://toast.asit.space/appcast.xml](https://toast.asit.space/appcast.xml) returns XML over HTTPS.

Optional: set **`GITHUB_REPO`** (e.g. `owner/repo`) if the repo slug differs from `asitkhanda/toast`.

## Releasing a new version

1. Bump version in `VercelStatus/Resources/Info.plist`:
   - `CFBundleShortVersionString` — semver (e.g. `0.2.0`)
   - `CFBundleVersion` — increment build number (e.g. `2`)
2. Commit and push to `main`.
3. Tag and push:

   ```bash
   git tag v0.2.0
   git push origin v0.2.0
   ```

The [Release workflow](.github/workflows/release.yml) will:

- Build and ad-hoc sign the app
- Create a DMG for manual install and a zip for Sparkle updates
- Sign the zip with Sparkle EdDSA
- Create a GitHub Release with both assets
- Update `web/public/appcast.xml` and push to `main`
- Trigger a Vercel redeploy of the appcast feed

Installed apps check `https://toast.asit.space/appcast.xml` automatically and via **Check for Updates…** in Settings.

## Distribution notes (no Apple Developer Program)

This project uses **ad-hoc code signing** (`codesign --sign -`) without notarization. Users may see Gatekeeper warnings on first install and occasionally after updates. Documented on the landing page and above.

CI builds are **arm64** (Apple Silicon). macOS 14+ is required.

## Development

Open in Xcode:

```bash
open VercelStatus/Package.swift
```

Or run a debug build:

```bash
cd VercelStatus
swift run
```
