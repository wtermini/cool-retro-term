#!/usr/bin/env bash
# Builds "Cool Retro Term.app", the native macOS front end, into macos/build/.
#
# Usage: ./build-app.sh [--debug] [--universal]
#   --debug      debug build instead of release
#   --universal  build for both Apple silicon and Intel
set -euo pipefail

cd "$(dirname "$0")"
MACOS_DIR=$(pwd)
REPO_DIR=$(cd .. && pwd)

CONFIG=release
ARCH_FLAGS=()
for arg in "$@"; do
    case "$arg" in
        --debug) CONFIG=debug ;;
        --universal) ARCH_FLAGS=(--arch arm64 --arch x86_64) ;;
        *) echo "unknown option: $arg" >&2; exit 1 ;;
    esac
done

# Resources shared with the Qt app: profiles, the font table and the fonts
# themselves. Also used directly by `swift run` during development.
RESOURCES="$MACOS_DIR/.build/resources"
rm -rf "$RESOURCES"
mkdir -p "$RESOURCES/Fonts"
python3 scripts/export-shared-data.py "$REPO_DIR" "$RESOURCES"
cp -R "$REPO_DIR/app/qml/fonts/." "$RESOURCES/Fonts/"
cp Shaders/CRT.metal "$RESOURCES/"

swift build -c "$CONFIG" ${ARCH_FLAGS[@]+"${ARCH_FLAGS[@]}"}
BIN_DIR=$(swift build -c "$CONFIG" ${ARCH_FLAGS[@]+"${ARCH_FLAGS[@]}"} --show-bin-path)

VERSION=$(git -C "$REPO_DIR" describe --tags --always 2>/dev/null | sed 's/^v//' || echo 0.0.0)
APP="$MACOS_DIR/build/Cool Retro Term.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/CoolRetroTerm" "$APP/Contents/MacOS/"
sed "s/__VERSION__/$VERSION/g" Info.plist > "$APP/Contents/Info.plist"
cp -R "$RESOURCES/." "$APP/Contents/Resources/"
cp "$REPO_DIR/app/icons/crt.icns" "$APP/Contents/Resources/"

# Ad-hoc signature so macOS will run the app on this machine.
codesign --force --sign - "$APP"

echo "Built $APP"
