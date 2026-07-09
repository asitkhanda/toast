# homebrew-toast-tap

Homebrew tap for [Toast](https://toast.asit.space) — a menu bar app (no Dock icon) to check your Vercel deployments live.

## Install

```bash
brew tap asitkhanda/toast-tap
brew trust asitkhanda/toast-tap
brew install --cask toast-app
```

Homebrew cannot run custom steps after `brew tap`, but it will refuse to install from an untrusted tap until you run `brew trust`. If you skip the trust step, `brew install` will tell you what to run. To trust only this cask instead of the whole tap:

```bash
brew trust --cask asitkhanda/toast-tap/toast-app
```

Toast updates automatically via Sparkle after install. Homebrew is only needed for the initial install or to reinstall.

## Updating the cask

GitHub repo: [asitkhanda/homebrew-toast-tap](https://github.com/asitkhanda/homebrew-toast-tap)

The cask is bumped automatically when a new version is released in [asitkhanda/toast](https://github.com/asitkhanda/toast). To bump manually, use the script in the main Toast repo:

```bash
../scripts/bump-homebrew-cask.sh <version> <dmg-sha256> Casks/toast-app.rb
```
