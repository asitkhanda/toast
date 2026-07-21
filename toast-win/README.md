# Toast for Windows (`toast-win`)

Native WinUI 3 system-tray app for live Vercel deployment status. Sibling to the macOS app in [`../Toast`](../Toast).

## Requirements

- Windows 10 1809+ (x64)
- .NET 8 SDK
- Windows App SDK workload (pulled via NuGet)

## Local build

```powershell
cd toast-win
./build.ps1 -SkipPack
```

Full Velopack package (writes `dist/Toast-{version}-win-x64-Setup.exe`):

```powershell
./build.ps1
```

Version is read from [`../Toast/Resources/Info.plist`](../Toast/Resources/Info.plist) so Mac and Windows stay aligned.

### Authenticode signing (optional)

```powershell
$env:WINDOWS_CERTIFICATE_P12 = "<base64-p12>"
$env:WINDOWS_CERTIFICATE_PASSWORD = "<password>"
./build.ps1 -Sign
```

CI uses the same secrets (`WINDOWS_CERTIFICATE_P12`, `WINDOWS_CERTIFICATE_PASSWORD`). If unset, the workflow still publishes an **unsigned** Setup.exe and never fails the Mac release.

## Architecture

| Project | Role |
|---------|------|
| `src/Toast.Core` | Vercel API client, models, poll/`DeploymentStore` |
| `src/Toast` | WinUI 3 tray UI, Credential Manager, PostHog, Velopack |
| `src/Toast.Watchdog` | Optional crash-relaunch helper |

### Security parity

- PAT stored only in **Windows Credential Manager** (`Toast/VercelPAT`, local-machine persist)
- Token never logged or sent to analytics
- Outbound: `api.vercel.com`, PostHog, GitHub Releases (updates)
- Prefer read-only token warning via `/v3/user/tokens` probe

### Feature parity (Mac)

- Onboarding (token → projects → background prefs)
- Tray status + popover list
- Settings (token, projects, notifications, startup, analytics)
- 5s / 60s poll loop
- Desktop notifications on build → ready/error
- Crash prompt + analytics rollout notice
- Velopack auto-update (Sparkle analogue)

## Release

Tag `vX.Y.Z` matching Info.plist. GitHub Actions:

1. `release-mac` — DMG, Sparkle zip, Homebrew, appcast (unchanged behavior)
2. `release-win` — Setup.exe (continue-on-error)
3. `publish` — GitHub Release with Mac assets always; Windows when present; shared `SHA256SUMS.txt`

Asset name: `Toast-{version}-win-x64-Setup.exe`

## Regression checklist (dual release)

- [ ] Mac DMG/zip still install; Sparkle update works
- [ ] Homebrew cask bump still correct
- [ ] `/download` and `/download?platform=mac` → DMG
- [ ] `/download?platform=windows` → Setup.exe when present; Mac still publishes if Windows CI fails
- [ ] Appcast has no Windows Setup.exe
- [ ] Token never appears in logs/analytics
- [ ] Credential Manager entry created on connect and removed on disconnect
