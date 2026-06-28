# Vercel Status

A macOS menu bar app that shows live Vercel deployment status for your watched projects.

- **Download:** [github.com/asitkhanda/toast/releases/latest](https://github.com/asitkhanda/toast/releases/latest)
- **Update feed:** [toast.asit.space/appcast.xml](https://toast.asit.space/appcast.xml)
- **Landing page:** [toast.asit.space](https://toast.asit.space)

## Install

1. Download the latest `Vercel-Status-X.Y.Z.zip` from [GitHub Releases](https://github.com/asitkhanda/toast/releases).
2. Unzip and move **Vercel Status.app** to Applications (or anywhere you prefer).
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
├── web/                   # Static site for Vercel (appcast + landing page)
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
4. Deploy (static site — no build command required).
5. Add custom domain **`toast.asit.space`** in Vercel → Domains.
6. In your DNS provider for `asit.space`, add the CNAME record Vercel shows (typically `toast` → `cname.vercel-dns.com`).
7. Verify [https://toast.asit.space/](https://toast.asit.space/) shows the landing page and [https://toast.asit.space/appcast.xml](https://toast.asit.space/appcast.xml) returns XML over HTTPS.

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
- Sign the zip with Sparkle EdDSA
- Create a GitHub Release with the zip asset
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
