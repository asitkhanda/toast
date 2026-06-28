#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

PURGE_LOCAL=false
for arg in "$@"; do
  case "$arg" in
    --purge-local) PURGE_LOCAL=true ;;
  esac
done

swift package resolve

GENERATE_KEYS="$(find .build/artifacts -path "*/Sparkle/bin/generate_keys" | head -1)"
if [ -z "$GENERATE_KEYS" ]; then
  echo "Error: generate_keys not found. Run 'swift package resolve' first."
  exit 1
fi

echo "Generating Sparkle EdDSA keys (saved to macOS Keychain)..."
"$GENERATE_KEYS"

PUBLIC_KEY="$("$GENERATE_KEYS" -p | tail -1 | tr -d '[:space:]')"
if [ -z "$PUBLIC_KEY" ]; then
  echo "Error: could not read public key from Keychain."
  exit 1
fi

PRIVATE_KEY_FILE="$ROOT/sparkle-private-key"
"$GENERATE_KEYS" -x "$PRIVATE_KEY_FILE"

# Remove accidental export from older script versions.
rm -f "$ROOT/public-key"

PLIST="$ROOT/Resources/Info.plist"
/usr/libexec/PlistBuddy -c "Set :SUPublicEDKey $PUBLIC_KEY" "$PLIST"

echo ""
echo "Sparkle keys ready."
echo ""
echo "Public key (also written to Info.plist):"
echo "  $PUBLIC_KEY"
echo ""
echo "Private key exported to:"
echo "  $PRIVATE_KEY_FILE"
echo ""
echo "Add the private key to GitHub repo secrets as SPARKLE_PRIVATE_KEY:"
echo "  cat \"$PRIVATE_KEY_FILE\""
echo ""
echo "Security:"
echo "  - Never commit the private key (it is gitignored)."
echo "  - Store a backup in a password manager, not in the repo."
echo "  - Delete the local export after uploading to GitHub Secrets:"
echo "      rm \"$PRIVATE_KEY_FILE\""
echo "  - Or rerun this script with --purge-local after the secret is configured."

if [ "$PURGE_LOCAL" = true ]; then
  rm -f "$PRIVATE_KEY_FILE"
  echo ""
  echo "Deleted local private key export."
fi
