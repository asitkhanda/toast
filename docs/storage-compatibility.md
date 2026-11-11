# Toast Storage Compatibility Contract

This document records identifiers that must not change without an explicit
migration and rollback plan.

## macOS

- Bundle ID: `com.toast.app`
- Login helper bundle ID: `com.toast.app.launcher`
- Keychain service: `com.toast.app`
- Keychain account: `vercel-pat`
- Cloudflare Keychain account: `cloudflare-api-token`
- Saved `watchedProjects` entries without a `provider` field decode as Vercel
- Application Support directory: `com.toast.app`
- Sparkle feed: `https://toast.asit.space/appcast.xml`
- Sparkle public key: `SUPublicEDKey` in `Toast/Resources/Info.plist`

The token remains protected by `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`
and is never migrated by deleting the old item first. Any future migration
must successfully read and validate the replacement before removing the old
item.

## Windows

- Velopack package ID: `Toast`
- Velopack update channel: `win`
- Credential Manager target: `Toast/VercelPAT`
- Preference directory: `%LOCALAPPDATA%/Toast`
- Runtime state file: `%LOCALAPPDATA%/Toast/runtime.json`

Existing JSON preference keys include:
`onboardingComplete`, `showStatusText`, `notificationsEnabled`,
`launchAtLogin`, `runInBackground`, `relaunchOnCrash`,
`backgroundBehaviorConfigured`, `selectedTeamId`, and `watchedProjects`.

## Release identity

- Homebrew cask: `toast-app`
- DMG asset: `Toast-{version}.dmg`
- Sparkle asset: `Toast-{version}.zip`
- Windows installer: `Toast-{version}-win-x64-Setup.exe`

These names and URLs are compatibility-sensitive for existing users and
should not be changed as part of refactoring.
