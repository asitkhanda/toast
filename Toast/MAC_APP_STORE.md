# Mac App Store Guide

This document covers the **Mac App Store (MAS)** track for Toast. Direct download (DMG, Sparkle, Homebrew) stays on the existing `build.sh` path.

**Windows** is a separate track (`toast-win/`, Velopack Setup.exe on the same GitHub Release). MAS entitlement/sandbox changes do not apply to Windows builds.

## Two distribution channels

| | Direct download | Mac App Store |
|---|---|---|
| Build script | `./build.sh` | `./build-mas.sh` |
| Updates | Sparkle | App Store |
| Signing | Developer ID Application | Apple Distribution |
| Sandbox | No | Yes (required) |
| Sparkle | Yes | No |

Both channels can coexist. They are separate builds from the same source using the `APPSTORE=1` compile flag.

---

## 1. Apple Developer setup

### App ID

1. [Certificates, Identifiers & Profiles](https://developer.apple.com/account/resources/identifiers/list) → **Identifiers** → **+**
2. Choose **App IDs** → **App**
3. Bundle ID: `com.toast.app`
4. Enable capabilities if prompted:
   - App Sandbox
   - Network (Outgoing Connections)

### Certificates (in addition to Developer ID)

Create these under **Certificates**:

| Certificate | Purpose |
|---|---|
| **Apple Distribution** | Sign the Mac App Store app |
| **Mac Installer Distribution** | Sign the `.pkg` (optional; Transporter accepts signed `.app` too) |

Use **G2 Sub-CA (Xcode 11.4.1 or later)** when asked.

### Provisioning profile

1. **Profiles** → **+** → **Mac App Store Connect**
2. App ID: `com.toast.app`
3. Select your **Apple Distribution** certificate
4. Download as `Toast_Mac_App_Store.provisionprofile`

---

## 2. App Store Connect listing

1. [appstoreconnect.apple.com](https://appstoreconnect.apple.com) → **My Apps** → **+** → **New App**
2. Platform: **macOS**
3. Name: **Toast**
4. Primary language: English
5. Bundle ID: `com.toast.app`
6. SKU: e.g. `toast-macos`

### Required metadata

| Field | Value |
|---|---|
| Privacy Policy URL | `https://toast.asit.space/privacy` |
| Support URL | `https://toast.asit.space` |
| Category | Developer Tools or Utilities |
| Price | Free |

### Screenshots

Capture at 1280×800 (or Apple’s current required sizes):

- Menu bar icon + popover with deployment status
- Settings screen
- Onboarding / token entry

### App Privacy

Declare PostHog analytics (matching your privacy policy):

- Product interaction (optional, if analytics enabled)
- Crash data
- Device ID (anonymous PostHog ID)

Mark data as **not linked to identity** and **not used for tracking** if that matches your PostHog config.

### Review notes

Include something like:

> Toast requires a read-only Vercel personal access token to show deployment status.  
> Test token: `[provide a read-only token scoped to a demo team]`  
> Steps: Launch → paste token → select team → pick projects.

Apple reviewers need a working token.

---

## 3. Build locally

```bash
cd Toast

export SIGN_IDENTITY="Apple Distribution: Your Name (TEAMID)"
export PROVISIONING_PROFILE_PATH="$HOME/Downloads/Toast_Mac_App_Store.provisionprofile"

./build-mas.sh
```

Output: `dist/mas/Toast.app`

### Optional: create a signed installer package

```bash
export CREATE_PKG=1
export INSTALLER_SIGN_IDENTITY="3rd Party Mac Developer Installer: Your Name (TEAMID)"
./build-mas.sh
```

Output: `dist/mas/Toast.pkg`

### Switch back to direct-download builds

The MAS build sets `APPSTORE=1` and runs `swift package reset`. Before a normal release:

```bash
unset APPSTORE
swift package reset
./build.sh
```

---

## 4. Upload to App Store Connect

### Option A — Transporter (recommended for script builds)

1. Download [Transporter](https://apps.apple.com/app/transporter/id1450874784) from the Mac App Store
2. Drag `dist/mas/Toast.app` or `Toast.pkg` into Transporter
3. Deliver

### Option B — Xcode

1. Open `Toast/Package.swift` in Xcode
2. Create a scheme with `APPSTORE=1` environment variable
3. Product → Archive → Distribute App → App Store Connect

---

## 5. Submit for review

1. In App Store Connect, open your app → **macOS App**
2. Create a new version (e.g. `0.4.2`)
3. Select the uploaded build
4. Fill in **What’s New**
5. Submit for review

Review typically takes 1–7 days.

---

## What changed in the MAS build

Code changes for App Store compliance:

- **`APPSTORE=1`** — excludes Sparkle dependency and defines compile flag
- **App Sandbox** — `Toast.mas.entitlements` (network client + keychain access group)
- **No Sparkle** — update UI hidden; App Store delivers updates
- **Keychain** — sandbox-friendly storage (no `SecAccess` trusted-app list)
- **Info.plist** — `SUFeedURL` and `SUPublicEDKey` stripped from MAS bundle

---

## Checklist before first submission

- [ ] App ID `com.toast.app` registered
- [ ] Apple Distribution certificate created
- [ ] Mac App Store provisioning profile downloaded
- [ ] App Store Connect app record created
- [ ] Screenshots uploaded
- [ ] Privacy questionnaire completed
- [ ] Review notes include test Vercel token
- [ ] `./build-mas.sh` succeeds locally
- [ ] Sandboxed app tested: token save, API calls, launch at login
- [ ] Upload via Transporter succeeds
- [ ] Build appears in App Store Connect

---

## Troubleshooting

### Token won't save in sandbox build

Ensure the app is signed with the Mac App Store profile so `keychain-access-groups` resolves correctly.

### Login item not working

Both the main app and `ToastLauncher` must be signed with the same team. Approve in **System Settings → General → Login Items**.

### Upload rejected for entitlements

MAS builds must use `Toast.mas.entitlements`, not `Toast.entitlements` or `Toast.adhoc.entitlements`.

### Sparkle symbols missing after switching builds

Run `swift package reset && swift package resolve` when switching between `./build.sh` and `./build-mas.sh`.
