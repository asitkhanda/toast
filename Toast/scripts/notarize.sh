#!/usr/bin/env bash
# Submit a .app or .dmg to Apple notarization and staple the ticket.
#
# Idempotent: safe to re-run. Resumes in-progress submissions instead of
# submitting duplicates. Local builds wait indefinitely; CI uses NOTARIZE_TIMEOUT.
set -euo pipefail

ARTIFACT="${1:?Usage: notarize.sh <Toast.app|Toast.dmg>}"
ARTIFACT="$(cd "$(dirname "$ARTIFACT")" && pwd)/$(basename "$ARTIFACT")"
ARTIFACT_NAME="$(basename "$ARTIFACT")"
STATE_FILE="${ARTIFACT}.notarize-state"

if [[ ! -e "$ARTIFACT" ]]; then
    echo "Error: artifact not found at $ARTIFACT"
    exit 1
fi

SUBMIT_ZIP=""
cleanup() {
    if [[ -n "$SUBMIT_ZIP" && -f "$SUBMIT_ZIP" ]]; then
        rm -f "$SUBMIT_ZIP"
    fi
}
trap cleanup EXIT

submit_args=()
if [[ -n "${APPLE_API_KEY_PATH:-}" && -n "${APPLE_API_KEY_ID:-}" && -n "${APPLE_API_ISSUER_ID:-}" ]]; then
    submit_args=(
        --key "$APPLE_API_KEY_PATH"
        --key-id "$APPLE_API_KEY_ID"
        --issuer "$APPLE_API_ISSUER_ID"
    )
elif [[ -n "${APPLE_ID:-}" && -n "${APPLE_NOTARIZATION_PASSWORD:-}" && -n "${APPLE_TEAM_ID:-}" ]]; then
    submit_args=(
        --apple-id "$APPLE_ID"
        --password "$APPLE_NOTARIZATION_PASSWORD"
        --team-id "$APPLE_TEAM_ID"
    )
else
    echo "Error: notarization credentials are not configured."
    echo "Set APPLE_API_KEY_PATH, APPLE_API_KEY_ID, APPLE_API_ISSUER_ID"
    echo "or APPLE_ID, APPLE_NOTARIZATION_PASSWORD, APPLE_TEAM_ID."
    exit 1
fi

read_state() {
    local key="$1"
    if [[ -f "$STATE_FILE" ]]; then
        grep "^${key}=" "$STATE_FILE" 2>/dev/null | cut -d= -f2- || true
    fi
}

write_state() {
    local sha256="$1" submission_id="$2" status="$3"
    cat > "$STATE_FILE" <<EOF
ARTIFACT=$ARTIFACT
SHA256=$sha256
SUBMISSION_ID=$submission_id
STATUS=$status
UPDATED_AT=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
EOF
}

artifact_sha256() {
    if [[ "$ARTIFACT" == *.app ]]; then
        local tmp_zip
        tmp_zip="$(mktemp -t toast-notarize-check).zip"
        ditto -c -k --keepParent "$ARTIFACT" "$tmp_zip"
        shasum -a 256 "$tmp_zip" | awk '{print $1}'
        rm -f "$tmp_zip"
    else
        shasum -a 256 "$ARTIFACT" | awk '{print $1}'
    fi
}

is_stapled() {
    xcrun stapler validate "$ARTIFACT" >/dev/null 2>&1
}

notary_info() {
    local submission_id="$1"
    xcrun notarytool info "$submission_id" "${submit_args[@]}" 2>&1
}

notary_status() {
    local submission_id="$1"
    notary_info "$submission_id" | awk -F': ' '/^[[:space:]]*status:/{print $2; exit}'
}

notary_log() {
    local submission_id="$1"
    xcrun notarytool log "$submission_id" "${submit_args[@]}" 2>&1
}

parse_timeout_seconds() {
    local timeout="${1:-}"
    if [[ -z "$timeout" ]]; then
        echo ""
        return 0
    fi

    if [[ "$timeout" =~ ^[0-9]+$ ]]; then
        echo "$timeout"
        return 0
    fi

    if [[ "$timeout" =~ ^([0-9]+)(s|m|h)$ ]]; then
        local value="${BASH_REMATCH[1]}"
        local unit="${BASH_REMATCH[2]}"
        case "$unit" in
            s) echo "$value" ;;
            m) echo $((value * 60)) ;;
            h) echo $((value * 3600)) ;;
        esac
        return 0
    fi

    echo "Error: invalid NOTARIZE_TIMEOUT value: $timeout (use 900, 15m, or 48h)" >&2
    exit 1
}

poll_submission() {
    local submission_id="$1"
    local max_seconds="$2"
    local start_ts
    start_ts="$(date +%s)"

    echo "Waiting for Apple to finish processing submission $submission_id..."
    if [[ -n "$max_seconds" ]]; then
        echo "Poll timeout: ${max_seconds}s (set NOTARIZE_TIMEOUT to change; unset locally for no limit)"
    else
        echo "No timeout — will keep polling until Apple responds. Safe to Ctrl+C and re-run ./build.sh to resume."
    fi

    while true; do
        local status
        status="$(notary_status "$submission_id")"
        echo "$(date '+%H:%M:%S')  status: ${status:-unknown}"

        case "$status" in
            Accepted)
                write_state "$(read_state SHA256)" "$submission_id" "accepted"
                return 0
                ;;
            Invalid)
                write_state "$(read_state SHA256)" "$submission_id" "invalid"
                echo ""
                echo "Notarization rejected for $ARTIFACT_NAME. Apple log:"
                notary_log "$submission_id"
                echo ""
                echo "Fix the signing issues above, then re-run ./build.sh"
                exit 1
                ;;
            In\ Progress|"")
                if [[ -n "$max_seconds" ]]; then
                    local elapsed=$(( $(date +%s) - start_ts ))
                    if (( elapsed >= max_seconds )); then
                        write_state "$(read_state SHA256)" "$submission_id" "in_progress"
                        echo ""
                        echo "Still in progress after ${max_seconds}s."
                        echo "Submission ID: $submission_id"
                        echo "Re-run ./build.sh later — it will resume this submission automatically."
                        exit 1
                    fi
                fi
                sleep 30
                ;;
            *)
                echo "Unexpected notarization status: $status"
                sleep 30
                ;;
        esac
    done
}

prepare_submit_path() {
    if [[ "$ARTIFACT" == *.app ]]; then
        SUBMIT_ZIP="$(mktemp -t toast-notarize).zip"
        echo "Creating notarization archive for app..." >&2
        ditto -c -k --keepParent "$ARTIFACT" "$SUBMIT_ZIP"
        SUBMIT_PATH="$SUBMIT_ZIP"
    else
        SUBMIT_PATH="$ARTIFACT"
    fi
}

submit_new() {
    local sha256="$1"
    prepare_submit_path

    echo "Submitting $ARTIFACT_NAME to Apple notarization..." >&2
    local output submission_id
    output="$(xcrun notarytool submit "$SUBMIT_PATH" "${submit_args[@]}" 2>&1)"
    echo "$output" >&2

    submission_id="$(echo "$output" | awk '/^[[:space:]]*id:/{print $2; exit}')"
    if [[ -z "$submission_id" ]]; then
        echo "Error: could not parse submission id from notarytool output" >&2
        exit 1
    fi

    write_state "$sha256" "$submission_id" "in_progress"
    echo "$submission_id"
}

find_in_progress_submission() {
    local current_id=""
    while IFS= read -r line; do
        if [[ "$line" =~ ^[[:space:]]*id:[[:space:]]*(.+)$ ]]; then
            current_id="${BASH_REMATCH[1]}"
        elif [[ "$line" =~ ^[[:space:]]*status:[[:space:]]*In\ Progress[[:space:]]*$ ]]; then
            if [[ -n "$current_id" ]]; then
                echo "$current_id"
                return 0
            fi
        fi
    done < <(xcrun notarytool history "${submit_args[@]}" 2>&1 | head -80)
}

# --- Main flow ---

if is_stapled; then
    echo "$ARTIFACT_NAME is already notarized and stapled — skipping."
    if [[ -f "$STATE_FILE" ]]; then
        write_state "$(read_state SHA256)" "$(read_state SUBMISSION_ID)" "stapled"
    fi
    exit 0
fi

CURRENT_SHA="$(artifact_sha256)"
STORED_SHA="$(read_state SHA256)"
STORED_ID="$(read_state SUBMISSION_ID)"
STORED_STATUS="$(read_state STATUS)"

submission_id=""

if [[ -n "$STORED_ID" && "$STORED_SHA" == "$CURRENT_SHA" ]]; then
    live_status="$(notary_status "$STORED_ID")"
    echo "Found existing submission for $ARTIFACT_NAME ($STORED_ID, cached: $STORED_STATUS, live: $live_status)"

    case "$live_status" in
        Accepted)
            submission_id="$STORED_ID"
            write_state "$CURRENT_SHA" "$submission_id" "accepted"
            ;;
        In\ Progress)
            submission_id="$STORED_ID"
            echo "Resuming in-progress submission (not submitting a duplicate)."
            ;;
        Invalid)
            write_state "$CURRENT_SHA" "$STORED_ID" "invalid"
            echo "Previous submission was rejected. Apple log:"
            notary_log "$STORED_ID"
            echo ""
            echo "Rebuild with a fixed signature, then re-run ./build.sh"
            exit 1
            ;;
        *)
            echo "Could not read status for $STORED_ID — submitting a new request."
            submission_id="$(submit_new "$CURRENT_SHA")"
            ;;
    esac
elif [[ -n "$STORED_ID" && "$STORED_SHA" != "$CURRENT_SHA" ]]; then
    echo "Artifact changed since last submission — submitting a new request."
    submission_id="$(submit_new "$CURRENT_SHA")"
elif [[ -n "${NOTARIZE_RESUME_ID:-}" ]]; then
    echo "Resuming submission from NOTARIZE_RESUME_ID=$NOTARIZE_RESUME_ID"
    write_state "$CURRENT_SHA" "$NOTARIZE_RESUME_ID" "in_progress"
    submission_id="$NOTARIZE_RESUME_ID"
else
    recovered_id="$(find_in_progress_submission || true)"
    if [[ -n "$recovered_id" ]]; then
        echo "Recovered in-progress submission from Apple history: $recovered_id"
        write_state "$CURRENT_SHA" "$recovered_id" "in_progress"
        submission_id="$recovered_id"
    else
        submission_id="$(submit_new "$CURRENT_SHA")"
    fi
fi

if [[ "$(read_state STATUS)" != "accepted" ]]; then
    max_seconds=""
    if [[ -n "${NOTARIZE_TIMEOUT:-}" ]]; then
        max_seconds="$(parse_timeout_seconds "$NOTARIZE_TIMEOUT")"
    elif [[ -n "${GITHUB_ACTIONS:-}" ]]; then
        max_seconds="900"
    fi
    poll_submission "$submission_id" "$max_seconds"
fi

staple_with_retry() {
    # Apple's CDN can lag behind "Accepted" — stapler Error 65 / "Record not found"
    # is temporary. Retry with backoff instead of failing immediately.
    local max_attempts="${STAPLE_MAX_ATTEMPTS:-12}"
    local delay=10
    local attempt=1

    echo "Stapling notarization ticket to $ARTIFACT_NAME..."
    while (( attempt <= max_attempts )); do
        if xcrun stapler staple "$ARTIFACT" 2>&1; then
            xcrun stapler validate "$ARTIFACT"
            return 0
        fi

        if (( attempt == max_attempts )); then
            echo ""
            echo "Stapling still failing after ${max_attempts} attempts."
            echo "Notarization was Accepted — the ticket just isn't on Apple's CDN yet."
            echo "Re-run ./build.sh later; it will resume at stapling (no new submission)."
            exit 1
        fi

        echo "Ticket not on Apple's CDN yet (attempt ${attempt}/${max_attempts}). Retrying in ${delay}s..."
        sleep "$delay"
        if (( delay < 60 )); then
            delay=$(( delay + 10 ))
        fi
        attempt=$(( attempt + 1 ))
    done
}

staple_with_retry
write_state "$CURRENT_SHA" "$submission_id" "stapled"

echo "Notarized: $ARTIFACT"
