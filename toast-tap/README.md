# homebrew-toast-tap

Homebrew tap for [Toast](https://toast.asit.space) — a macOS menu bar app for live Vercel deployment status.

## Install

```bash
brew tap asitkhanda/toast-tap
brew install --cask toast-app
```

Toast updates automatically via Sparkle after install. Homebrew is only needed for the initial install or to reinstall.

## Updating the cask

The cask is bumped automatically when a new version is released in [asitkhanda/toast](https://github.com/asitkhanda/toast). To bump manually, use the script in the main Toast repo:

```bash
../scripts/bump-homebrew-cask.sh <version> <dmg-sha256> Casks/toast-app.rb
```
