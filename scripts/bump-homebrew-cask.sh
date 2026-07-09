#!/usr/bin/env bash
# Bump version and sha256 in the toast-app Homebrew cask.
# Usage: bump-homebrew-cask.sh <version> <dmg-sha256> [cask-file]
set -euo pipefail

VERSION="${1:?Usage: bump-homebrew-cask.sh <version> <dmg-sha256> [cask-file]}"
DMG_SHA="${2:?Usage: bump-homebrew-cask.sh <version> <dmg-sha256> [cask-file]}"
CASK_FILE="${3:-Casks/toast-app.rb}"

if [[ ! -f "$CASK_FILE" ]]; then
  echo "Cask file not found: $CASK_FILE"
  exit 1
fi

if [[ ! "$DMG_SHA" =~ ^[a-f0-9]{64}$ ]]; then
  echo "Invalid SHA256: $DMG_SHA"
  exit 1
fi

ruby - "$CASK_FILE" "$VERSION" "$DMG_SHA" <<'RUBY'
path, version, sha = ARGV
contents = File.read(path)
contents.sub!(/version "[^"]*"/, %(version "#{version}"))
contents.sub!(/sha256 "[^"]*"/, %(sha256 "#{sha}"))
File.write(path, contents)
RUBY

echo "Updated $CASK_FILE to version $VERSION"
