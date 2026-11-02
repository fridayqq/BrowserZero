#!/usr/bin/env bash
# Builds a release binary and assembles build/BrowserZero.app.
#
# Environment:
#   UNIVERSAL=1        build arm64 + x86_64 (needs full Xcode; used in CI)
#   SIGN_IDENTITY=...  sign with this identity (e.g. "Developer ID Application: …")
#                      using the hardened runtime; without it the app is ad-hoc signed.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

# Command Line Tools on macOS 27 lack the SwiftUI macro plugins for the newest SDK;
# fall back to the 26.5 SDK when it is installed and nothing else was chosen.
CLT_SDK=/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk
if [[ -z "${SDKROOT:-}" && -d "$CLT_SDK" && "$(xcode-select -p)" == /Library/Developer/CommandLineTools ]]; then
    export SDKROOT="$CLT_SDK"
fi

if [[ "${UNIVERSAL:-0}" == "1" ]]; then
    swift build -c release --arch arm64 --arch x86_64
    BIN="$ROOT/.build/apple/Products/Release/BrowserZero"
else
    swift build -c release
    BIN="$ROOT/.build/release/BrowserZero"
fi

APP="$ROOT/build/BrowserZero.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp "$BIN" "$APP/Contents/MacOS/BrowserZero"
cp "$ROOT/Support/Info.plist" "$APP/Contents/Info.plist"

if [[ -n "${SIGN_IDENTITY:-}" ]]; then
    codesign --force --options runtime --timestamp \
        --entitlements "$ROOT/Support/BrowserZero.entitlements" \
        --sign "$SIGN_IDENTITY" "$APP"
    echo "Signed with: $SIGN_IDENTITY"
else
    codesign --force --sign - "$APP"
    echo "Ad-hoc signed (no SIGN_IDENTITY)"
fi
codesign --verify --strict "$APP"
echo "Built $APP"
