#!/usr/bin/env bash
# Notarizes and staples build/BrowserZero.app with Apple's notary service.
# Skips quietly when the credentials are not configured.
#
#   NOTARY_KEY_P8      base64 of the App Store Connect API key (.p8)
#   NOTARY_KEY_ID      the key ID
#   NOTARY_ISSUER_ID   the issuer UUID
set -euo pipefail
umask 077

APP="${1:-build/BrowserZero.app}"

if [[ -z "${NOTARY_KEY_P8:-}" || -z "${NOTARY_KEY_ID:-}" || -z "${NOTARY_ISSUER_ID:-}" ]]; then
    echo "No notarization credentials configured; skipping."
    exit 0
fi
if [[ -z "${SIGN_IDENTITY:-}" ]]; then
    echo "Notarization needs a Developer ID signature, but SIGN_IDENTITY is empty" >&2
    exit 1
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
printf '%s' "$NOTARY_KEY_P8" | base64 --decode > "$WORK/key.p8"
ditto -c -k --keepParent "$APP" "$WORK/submit.zip"

xcrun notarytool submit "$WORK/submit.zip" \
    --key "$WORK/key.p8" --key-id "$NOTARY_KEY_ID" --issuer "$NOTARY_ISSUER_ID" --wait
xcrun stapler staple "$APP"
echo "Notarized and stapled $APP"
