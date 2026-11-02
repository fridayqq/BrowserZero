#!/usr/bin/env bash
# Imports a Developer ID certificate into a temporary keychain on CI and prints
# nothing secret. Skips quietly when the secrets are not configured, so the
# release falls back to an ad-hoc signed build.
#
#   SIGNING_CERT_P12       base64 of the exported .p12
#   SIGNING_CERT_PASSWORD  its password
set -euo pipefail
umask 077

if [[ -z "${SIGNING_CERT_P12:-}" || -z "${SIGNING_CERT_PASSWORD:-}" ]]; then
    echo "No signing certificate configured; the build will be ad-hoc signed."
    exit 0
fi

TMP="${RUNNER_TEMP:-$(mktemp -d)}"
KC="$TMP/browserzero-signing.keychain-db"
KC_PASS="$(uuidgen)"
P12="$TMP/cert.p12"

printf '%s' "$SIGNING_CERT_P12" | base64 --decode > "$P12"
security create-keychain -p "$KC_PASS" "$KC"
security set-keychain-settings -lut 3600 "$KC"
security unlock-keychain -p "$KC_PASS" "$KC"
security import "$P12" -k "$KC" -P "$SIGNING_CERT_PASSWORD" -T /usr/bin/codesign
security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$KC_PASS" "$KC" >/dev/null
security list-keychains -d user -s "$KC" $(security list-keychains -d user | tr -d '"')
rm -f "$P12"

IDENTITY="$(security find-identity -v -p codesigning "$KC" | awk -F'"' '/Developer ID Application/ {print $2; exit}')"
if [[ -z "$IDENTITY" ]]; then
    echo "No 'Developer ID Application' identity in the certificate" >&2
    exit 1
fi
echo "SIGN_IDENTITY=$IDENTITY" >> "${GITHUB_ENV:-/dev/null}"
echo "Imported signing identity: $IDENTITY"
