# Toast

A lightweight **menu bar (macOS)** and **system tray (Windows)** app for live Vercel deployment status.

| Platform | Install | Auto-update |
|----------|---------|-------------|
| **macOS** | [DMG](https://toast.asit.space/download?platform=mac) or Homebrew | Sparkle |
| **Windows** | [Setup.exe](https://toast.asit.space/download?platform=windows) | Velopack |

- **Landing page:** [toast.asit.space](https://toast.asit.space)
- **macOS update feed:** [toast.asit.space/appcast.xml](https://toast.asit.space/appcast.xml)
- **Source:** macOS in [`Toast/`](Toast/), Windows in [`toast-win/`](toast-win/) (same product version)

## Install

### macOS

1. Download from [toast.asit.space/download?platform=mac](https://toast.asit.space/download?platform=mac) (latest `.dmg`).
2. Open the DMG and drag **Toast** into **Applications**.
3. Double-click **Toast** in Applications and complete onboarding with a **read-only, team-scoped** [Vercel personal access token](https://vercel.com/account/tokens), then pick projects to watch.

The DMG includes a **How to Open Toast.txt** guide with the same steps. Automatic updates are delivered via [Sparkle](https://sparkle-project.org/) after the first install.

### Windows

1. Download from [toast.asit.space/download?platform=windows](https://toast.asit.space/download?platform=windows) (`Toast-{version}-win-x64-Setup.exe` on the GitHub Release).
2. Run the installer and launch **Toast** from the Start menu (lives in the system tray).
3. Complete the same onboarding with a read-only Vercel token.

Windows updates use [Velopack](https://velopack.io/). Until an Authenticode cert is configured, builds may be unsigned — verify `SHA256SUMS.txt` on the [GitHub release](https://github.com/asitkhanda/toast/releases) before installing.

**Try from source on Windows** (no installer yet / local build):

```powershell
git clone https://github.com/asitkhanda/toast.git
cd toast\toast-win
./build.ps1
# Installer: dist\Toast-0.4.1-win-x64-Setup.exe
```

Requires Windows x64 + [.NET 8 SDK](https://dotnet.microsoft.com/download/dotnet/8.0). Details: [toast-win/README.md](toast-win/README.md).

### Homebrew (macOS)

```bash
brew tap asitkhanda/toast-tap
brew trust asitkhanda/toast-tap
brew install --cask toast-app
```

Homebrew requires third-party taps to be explicitly trusted before install. If you skip `brew trust`, the install step will prompt you to run it. To trust only this cask: `brew trust --cask asitkhanda/toast-tap/toast-app`.

The cask is named `toast-app` to avoid a naming conflict with another Homebrew formula. Toast updates automatically via Sparkle after install — Homebrew is only needed for the initial install or to reinstall.

## Build locally

### macOS

```bash
cd Toast
./build.sh
open "dist/Toast.app"
```

Requires macOS 14+ and Xcode command-line tools.

### Windows

```powershell
cd toast-win
./build.ps1
```

See [toast-win/README.md](toast-win/README.md). Requires Windows + .NET 8 SDK.

## Repository layout

```
├── Toast/                 # macOS app (Swift + Sparkle)
│   ├── Resources/         # Info.plist, icon, DMG background + open guide
│   └── scripts/           # DMG background generator + installer packaging
├── toast-win/             # Windows app (WinUI 3 + Velopack)
│   ├── src/Toast.Core/    # Shared product logic (API, poll store)
│   ├── src/Toast/         # WinUI tray UI
│   └── build.ps1          # Publish + Velopack pack
├── web/                   # Static site + /download redirect (Vercel)
│   ├── api/download.ts    # Edge function → latest .dmg or Windows Setup.exe
│   └── public/            # Landing page + appcast feed
├── toast-tap/             # Homebrew tap (push to github.com/asitkhanda/homebrew-toast-tap)
│   └── Casks/toast-app.rb
└── .github/workflows/     # Release automation (mac + windows + publish)
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
7. Verify [https://toast.asit.space/](https://toast.asit.space/) shows the landing page, [https://toast.asit.space/download?platform=mac](https://toast.asit.space/download?platform=mac) redirects to the latest DMG, [https://toast.asit.space/download?platform=windows](https://toast.asit.space/download?platform=windows) resolves to the Windows Setup.exe when published, and [https://toast.asit.space/appcast.xml](https://toast.asit.space/appcast.xml) returns XML over HTTPS.

Optional: set **`GITHUB_REPO`** (e.g. `owner/repo`) if the repo slug differs from `asitkhanda/toast`.

## Releasing a new version

1. Bump version in `Toast/Resources/Info.plist` (source of truth for both platforms):
   - `CFBundleShortVersionString` — semver (e.g. `0.2.0`)
   - `CFBundleVersion` — increment build number (e.g. `2`)
2. Commit and push to `main`.
3. Tag and push:

   ```bash
   git tag v0.2.0
   git push origin v0.2.0
   ```

Optional Windows signing secrets: `WINDOWS_CERTIFICATE_P12` (base64), `WINDOWS_CERTIFICATE_PASSWORD`.

The [Release workflow](.github/workflows/release.yml) will:

- **Mac:** Build, Developer ID sign, and notarize the app and DMG; create a Sparkle zip; sign with Sparkle EdDSA; bump Homebrew; update `appcast.xml`
- **Windows:** Build WinUI app + Velopack `Toast-{version}-win-x64-Setup.exe` (optional Authenticode if secrets are set). Windows failures do **not** block the Mac release.
- **Publish:** Create a GitHub Release with Mac assets always, Windows Setup.exe when present, and a combined `SHA256SUMS.txt`

Installed macOS apps check `https://toast.asit.space/appcast.xml` automatically and via **Check for Updates…** in Settings. Windows apps update via Velopack from GitHub Releases.

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

**What may be collected:** app version, OS version, device architecture, anonymous feature usage (e.g. onboarding completed, settings toggles), API error types and HTTP status codes, crash stack traces, and optional feedback text if you use Send Feedback.

**What is not collected:** your Vercel token, team IDs, project names, deployment URLs, or personal identifiers.

You can disable analytics at any time in **Settings → Privacy → Help improve Toast**. See the [privacy policy](https://toast.asit.space/privacy) for details.

## Security

### Vercel tokens

- **macOS:** Tokens are stored in the Keychain with app-scoped access control (`SecAccess` + `WhenUnlockedThisDeviceOnly`).
- **Windows:** Tokens are stored in Windows Credential Manager (`Toast/VercelPAT`, local-machine persist).
- Tokens are loaded from the secret store only when needed for API calls — not kept in long-lived app state or pre-filled in Settings.
- Use a **read-only, team-scoped** Vercel personal access token. Toast warns if a token appears to have elevated account access (e.g. can list account tokens).
- Never commit tokens, `.env` files, or `Toast/sparkle-private-key`.

### Release integrity

- Each GitHub Release includes `SHA256SUMS.txt` for the DMG, Sparkle zip, and Windows Setup.exe (when present).
- Verify downloads before opening: `shasum -a 256 Toast-*.dmg` / `Toast-*-win-x64-Setup.exe` and compare with the release manifest.
- Sparkle updates are EdDSA-signed; the public key is embedded in the app (`SUPublicEDKey` in `Info.plist`).

### GitHub & CI

- Keep `SPARKLE_PRIVATE_KEY` in GitHub Actions secrets only — delete the local export after setup (`Toast/scripts/setup-sparkle-keys.sh --purge-local`).
- Enable branch protection on `main`: require PR reviews, block force pushes, and restrict who can push tags or run the Release workflow.

### Code signing & notarization

Releases are **Developer ID signed** and **Apple-notarized** so macOS opens Toast without Gatekeeper workarounds.

#### One-time Apple setup

1. In [Certificates, Identifiers & Profiles](https://developer.apple.com/account/resources/certificates/list), create a **Developer ID Application** certificate.
2. Export it from Keychain Access as a `.p12` file (remember the export password).
3. In [App Store Connect → Users and Access → Integrations → App Store Connect API](https://appstoreconnect.apple.com/access/integrations/api), create an API key with **Developer** access. Download the `.p8` file.

#### GitHub Actions secrets

Add these in **Settings → Secrets and variables → Actions**:

| Secret | Value |
|--------|--------|
| `APPLE_CERTIFICATE_P12` | Base64-encoded `.p12` (`base64 -i cert.p12 \| pbcopy`) |
| `APPLE_CERTIFICATE_PASSWORD` | Password used when exporting the `.p12` |
| `APPLE_API_KEY_ID` | App Store Connect API key ID |
| `APPLE_API_ISSUER_ID` | App Store Connect issuer ID |
| `APPLE_API_KEY` | Full contents of the `.p8` API key file |

Optional fallback (if you prefer app-specific password instead of API key):

| Secret | Value |
|--------|--------|
| `APPLE_ID` | Apple ID email |
| `APPLE_NOTARIZATION_PASSWORD` | App-specific password |
| `APPLE_TEAM_ID` | 10-character team ID |

Optional: `APPLE_SIGN_IDENTITY` — only needed if auto-detection fails (e.g. `Developer ID Application: Your Name (TEAMID)`).

#### Windows Authenticode (optional)

| Secret | Value |
|--------|--------|
| `WINDOWS_CERTIFICATE_P12` | Base64-encoded code-signing `.p12` / `.pfx` |
| `WINDOWS_CERTIFICATE_PASSWORD` | Password for that certificate |

If unset, CI still publishes an **unsigned** `Toast-*-win-x64-Setup.exe`. Mac release never depends on these secrets.

#### Local signed build

```bash
cd Toast
export SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)"
export NOTARIZE=1
export APPLE_API_KEY_PATH="$HOME/path/AuthKey_XXXXXX.p8"
export APPLE_API_KEY_ID="..."
export APPLE_API_ISSUER_ID="..."
./build.sh
```

Without `SIGN_IDENTITY`, `./build.sh` still produces an ad-hoc build for local development (uses `Toast.adhoc.entitlements` so Sparkle can load).

CI builds are **arm64** (Apple Silicon). macOS 14+ is required.

## Mac App Store (separate build)

Toast can also be built for the Mac App Store alongside direct download. See **[Toast/MAC_APP_STORE.md](Toast/MAC_APP_STORE.md)** for the full checklist.

Quick start:

```bash
cd Toast
export SIGN_IDENTITY="Apple Distribution: Your Name (TEAMID)"
export PROVISIONING_PROFILE_PATH="$HOME/Downloads/Toast_Mac_App_Store.provisionprofile"
./build-mas.sh
```

The MAS build is sandboxed, excludes Sparkle, and outputs to `dist/mas/Toast.app`.

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
