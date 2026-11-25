#!/usr/bin/env bash
# Copyright (c) 2026 cool-retro-term contributors
# https://github.com/Swordfish90/cool-retro-term
#
# This file is part of cool-retro-term.
#
# cool-retro-term is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.
#
# Builds "Cool Retro Term SE.app", the native macOS front end, into macos/build/.
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
APP="$MACOS_DIR/build/Cool Retro Term SE.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/CoolRetroTerm" "$APP/Contents/MacOS/"
sed "s/__VERSION__/$VERSION/g" Info.plist > "$APP/Contents/Info.plist"
cp -R "$RESOURCES/." "$APP/Contents/Resources/"
cp "$REPO_DIR/app/icons/crt.icns" "$APP/Contents/Resources/"
# SwiftPM resource bundles, if any dependency has them.
find "$BIN_DIR" -maxdepth 1 -name '*.bundle' -exec cp -R {} "$APP/Contents/Resources/" \;

# Licenses: the app's own (GPL-3.0), third-party notices and SwiftTerm's MIT
# license. Each font's license already sits next to it in Resources/Fonts.
SWIFTTERM_LICENSE="$MACOS_DIR/.build/checkouts/SwiftTerm/LICENSE"
if [ ! -f "$SWIFTTERM_LICENSE" ]; then
    echo "error: SwiftTerm's LICENSE not found at $SWIFTTERM_LICENSE" >&2
    exit 1
fi
mkdir -p "$APP/Contents/Resources/Licenses"
cp "$REPO_DIR/gpl-3.0.txt" "$APP/Contents/Resources/Licenses/COPYING.txt"
cp THIRD_PARTY_NOTICES.md "$APP/Contents/Resources/Licenses/"
cp "$SWIFTTERM_LICENSE" "$APP/Contents/Resources/Licenses/SwiftTerm-LICENSE.txt"

# Ad-hoc signature so macOS will run the app on this machine.
codesign --force --sign - "$APP"

echo "Built $APP"
