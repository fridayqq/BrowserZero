#!/usr/bin/env bash
# Builds a release binary and assembles build/BrowserZero.app (ad-hoc signed).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

export SDKROOT="${SDKROOT:-/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk}"

swift build -c release

APP="$ROOT/build/BrowserZero.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp "$ROOT/.build/release/BrowserZero" "$APP/Contents/MacOS/BrowserZero"
cp "$ROOT/Support/Info.plist" "$APP/Contents/Info.plist"

codesign --force --deep --sign - "$APP"
echo "Built $APP"
