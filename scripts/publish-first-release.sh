#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

REPO="${GITHUB_REPOSITORY:-asitkhanda/toast}"
OWNER="${REPO%%/*}"
NAME="${REPO##*/}"
PRIVATE_KEY_FILE="$ROOT/VercelStatus/sparkle-private-key"

if [ ! -f "$PRIVATE_KEY_FILE" ]; then
  echo "Missing $PRIVATE_KEY_FILE — run VercelStatus/scripts/setup-sparkle-keys.sh first."
  exit 1
fi

CREDS="$(printf 'protocol=https\nhost=github.com\n\n' | git credential fill)"
USERNAME="$(printf '%s\n' "$CREDS" | sed -n 's/^username=//p' | head -1)"
TOKEN="$(printf '%s\n' "$CREDS" | sed -n 's/^password=//p' | head -1)"

if [ -z "${TOKEN:-}" ]; then
  echo "No GitHub credentials found. Sign in with GitHub in Git or install gh auth login."
  exit 1
fi

auth_header="Authorization: Bearer ${TOKEN}"
accept_header="Accept: application/vnd.github+json"

echo "Ensuring GitHub repo exists: $REPO"
status="$(curl -s -o /dev/null -w "%{http_code}" -H "$auth_header" -H "$accept_header" "https://api.github.com/repos/$REPO")"
if [ "$status" = "404" ]; then
  curl -sS -X POST \
    -H "$auth_header" \
    -H "$accept_header" \
    "https://api.github.com/user/repos" \
    -d "{\"name\":\"$NAME\",\"description\":\"macOS menu bar app for Vercel deployment status\",\"private\":false}" \
    >/dev/null
  echo "Created https://github.com/$REPO"
elif [ "$status" = "200" ]; then
  echo "Repo already exists."
else
  echo "Unexpected GitHub API status for repo lookup: $status"
  exit 1
fi

if ! git remote get-url origin >/dev/null 2>&1; then
  git remote add origin "https://github.com/$REPO.git"
fi
git remote set-url origin "https://github.com/$REPO.git"

echo "Pushing main..."
git push -u origin main

echo "Setting SPARKLE_PRIVATE_KEY secret..."
VENV_DIR="$(mktemp -d)"
python3 -m venv "$VENV_DIR"
"$VENV_DIR/bin/pip" install pynacl -q

"$VENV_DIR/bin/python" - <<'PY' "$OWNER" "$NAME" "$PRIVATE_KEY_FILE" "$TOKEN"
import base64
import json
import sys
import urllib.request

owner, name, key_path, token = sys.argv[1:5]
secret_value = open(key_path, "r", encoding="utf-8").read().strip()

req = urllib.request.Request(
    f"https://api.github.com/repos/{owner}/{name}/actions/secrets/public-key",
    headers={
        "Authorization": f"Bearer {token}",
        "Accept": "application/vnd.github+json",
        "User-Agent": "toast-first-release",
    },
)
with urllib.request.urlopen(req) as resp:
    key_data = json.load(resp)

from nacl import encoding, public

public_key = public.PublicKey(key_data["key"].encode("utf-8"), encoding.Base64Encoder())
sealed_box = public.SealedBox(public_key)
encrypted = sealed_box.encrypt(secret_value.encode("utf-8"))
encrypted_value = base64.b64encode(encrypted).decode("utf-8")

payload = json.dumps(
    {
        "encrypted_value": encrypted_value,
        "key_id": key_data["key_id"],
    }
).encode("utf-8")

put_req = urllib.request.Request(
    f"https://api.github.com/repos/{owner}/{name}/actions/secrets/SPARKLE_PRIVATE_KEY",
    data=payload,
    method="PUT",
    headers={
        "Authorization": f"Bearer {token}",
        "Accept": "application/vnd.github+json",
        "Content-Type": "application/json",
        "User-Agent": "toast-first-release",
    },
)
with urllib.request.urlopen(put_req) as resp:
    resp.read()

print("SPARKLE_PRIVATE_KEY secret configured.")
PY

rm -rf "$VENV_DIR"

echo "Creating and pushing tag v0.1.0..."
git tag -f v0.1.0
git push origin v0.1.0

echo ""
echo "Done."
echo "  Repo: https://github.com/$REPO"
echo "  Release workflow: https://github.com/$REPO/actions"
echo "  After CI finishes, verify:"
echo "    https://github.com/$REPO/releases/tag/v0.1.0"
echo "    https://toast.asit.space/appcast.xml (once Vercel is connected)"
