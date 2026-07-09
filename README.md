# Toast

A macOS menu bar app that shows live Vercel deployment status for your watched projects.

- **Download:** [toast.asit.space/download](https://toast.asit.space/download)
- **Update feed:** [toast.asit.space/appcast.xml](https://toast.asit.space/appcast.xml)
- **Landing page:** [toast.asit.space](https://toast.asit.space)

## Install

1. Download from [toast.asit.space/download](https://toast.asit.space/download) (redirects to the latest `.dmg`).
2. Open the DMG and drag **Toast** into **Applications** (checkpoint 1 — also shown on the DMG background).
3. **Allow first launch** (checkpoint 2 — Toast is not notarized yet):
   - **Recommended:** in Applications, right-click **Toast** → **Open** → **Open**.
   - **Fallback:** double-click once (expect the warning), then **System Settings → Privacy & Security → Open Anyway**.
4. Complete onboarding with a **read-only, team-scoped** [Vercel personal access token](https://vercel.com/account/tokens), then pick projects to watch (checkpoint 3).

The DMG includes a **How to Open Toast.txt** guide with the same steps. Automatic updates are delivered via [Sparkle](https://sparkle-project.org/) after the first install.

### Homebrew

```bash
brew tap asitkhanda/toast-tap
brew install --cask toast-app
```

The cask is named `toast-app` to avoid a naming conflict with another Homebrew formula. Toast updates automatically via Sparkle after install — Homebrew is only needed for the initial install or to reinstall.

## Build locally

```bash
cd Toast
./build.sh
open "dist/Toast.app"
```

Requires macOS 14+ and Xcode command-line tools.

## Repository layout

```
├── Toast/                 # macOS app (Swift + Sparkle)
│   ├── Resources/         # Info.plist, icon, DMG background + open guide
│   └── scripts/           # DMG background generator + installer packaging
├── web/                   # Static site + /download redirect (Vercel)
│   ├── api/download.ts    # Edge function → latest .dmg on GitHub Releases
│   └── public/            # Landing page + appcast feed
├── toast-tap/             # Homebrew tap (push to github.com/asitkhanda/homebrew-toast-tap)
│   └── Casks/toast-app.rb
└── .github/workflows/     # Release automation
```

## Sparkle signing keys (one-time setup)

Before your first release, generate EdDSA keys on your Mac:

```bash
cd Toast
chmod +x scripts/setup-sparkle-keys.sh
./scripts/setup-sparkle-keys.sh
```

Then:

1. The script updates `SUPublicEDKey` in `Resources/Info.plist` automatically.
2. Add the **private key** to GitHub → **Settings → Secrets and variables → Actions** as `SPARKLE_PRIVATE_KEY` (paste contents of `Toast/sparkle-private-key`).

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

1. Bump version in `Toast/Resources/Info.plist`:
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
- Bump the Homebrew cask in [asitkhanda/homebrew-toast-tap](https://github.com/asitkhanda/homebrew-toast-tap)
- Trigger a Vercel redeploy of the appcast feed

Installed apps check `https://toast.asit.space/appcast.xml` automatically and via **Check for Updates…** in Settings.

### Homebrew tap setup (one-time)

Push the `toast-tap/` directory to a public GitHub repo named `homebrew-toast-tap` (Homebrew requires the `homebrew-` prefix):

```bash
cd toast-tap
git init
git add .
git commit -m "Add toast-app cask"
git branch -M main
git remote add origin git@github.com:asitkhanda/homebrew-toast-tap.git
git push -u origin main
```

The Release workflow bumps `Casks/toast-app.rb` automatically. If the tap repo is private or under a different account, add a `HOMEBREW_TAP_TOKEN` secret with push access.

## Analytics

Toast includes optional anonymous product analytics (“Help improve Toast” in Settings; on by default). When enabled, the app sends usage and diagnostic data to [PostHog](https://posthog.com) to help improve stability and understand feature usage.

**What may be collected:** app version, macOS version, device architecture, anonymous feature usage (e.g. onboarding completed, settings toggles), API error types and HTTP status codes, crash stack traces, and optional feedback text if you use Send Feedback.

**What is not collected:** your Vercel token, team IDs, project names, deployment URLs, or personal identifiers.

You can disable analytics at any time in **Settings → Privacy → Help improve Toast**. See the [privacy policy](https://toast.asit.space/privacy) for details.

## Security

### Vercel tokens

- Tokens are stored in the macOS Keychain with app-scoped access control (`SecAccess` + `WhenUnlockedThisDeviceOnly`).
- Tokens are loaded from Keychain only when needed for API calls — not kept in long-lived app state or pre-filled in Settings.
- Use a **read-only, team-scoped** Vercel personal access token. Toast warns if a token appears to have elevated account access (e.g. can list account tokens).
- Never commit tokens, `.env` files, or `Toast/sparkle-private-key`.

### Release integrity

- Each GitHub Release includes `SHA256SUMS.txt` for the DMG and Sparkle zip.
- Verify downloads before opening: `shasum -a 256 Toast-*.dmg` and compare with the release manifest.
- Sparkle updates are EdDSA-signed; the public key is embedded in the app (`SUPublicEDKey` in `Info.plist`).

### GitHub & CI

- Keep `SPARKLE_PRIVATE_KEY` in GitHub Actions secrets only — delete the local export after setup (`Toast/scripts/setup-sparkle-keys.sh --purge-local`).
- Enable branch protection on `main`: require PR reviews, block force pushes, and restrict who can push tags or run the Release workflow.

### Code signing

This project currently uses **ad-hoc signing** without notarization. Users may see Gatekeeper warnings on first install and occasionally after updates.

`com.apple.security.cs.disable-library-validation` is required so the ad-hoc-signed app can load the embedded Sparkle.framework (signed by a different identity). Remove it only when the app and all embedded frameworks share the same Developer ID signature.

When you join the Apple Developer Program, switch to Developer ID signing + notarization for stronger install/update trust.

CI builds are **arm64** (Apple Silicon). macOS 14+ is required.

## Development

Open in Xcode:

```bash
open Toast/Package.swift
```

Or run a debug build:

```bash
cd Toast
swift run
```
