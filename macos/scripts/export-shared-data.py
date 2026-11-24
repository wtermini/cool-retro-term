#!/usr/bin/env python3
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
"""Export the built-in profiles and bundled font table from the Qt app.

The native macOS app reads the same profiles and fonts as the Qt app. This
script pulls them out of app/qml/ApplicationSettings.qml and
app/fontmanager.cpp into JSON, so the two front ends never drift apart.

Usage: export-shared-data.py <repo-root> <output-dir>
"""
import json
import re
import sys
from pathlib import Path


def export_profiles(repo: Path):
    qml = (repo / "app/qml/ApplicationSettings.qml").read_text()
    pattern = re.compile(
        r'ListElement\s*\{\s*text:\s*"([^"]+)"\s*obj_string:\s*\'(\{.*?\})\'', re.S)
    profiles = []
    for name, body in pattern.findall(qml):
        profile = json.loads(body)
        profile["name"] = name
        profiles.append(profile)
    if not profiles:
        sys.exit("no profiles found in ApplicationSettings.qml")
    return profiles


def export_fonts(repo: Path):
    cpp = (repo / "app/fontmanager.cpp").read_text()
    pattern = re.compile(
        r'addBundledFont\(\s*"([^"]+)",\s*"([^"]+)",\s*":/fonts/([^"]+)",\s*'
        r'([\d.]+),\s*(\d+),\s*(true|false)(?:,\s*"([^"]*)")?\s*\)', re.S)
    fonts = []
    for fid, name, path, scale, pixel_size, low_res, fallback in pattern.findall(cpp):
        fonts.append({
            "id": fid,
            "name": name,
            "file": path,
            "baseWidth": float(scale),
            "pixelSize": int(pixel_size),
            "lowResolution": low_res == "true",
            "fallback": fallback or None,
        })
    if not fonts:
        sys.exit("no fonts found in fontmanager.cpp")
    return fonts


def main():
    repo, out = Path(sys.argv[1]), Path(sys.argv[2])
    out.mkdir(parents=True, exist_ok=True)
    (out / "profiles.json").write_text(json.dumps(export_profiles(repo), indent=2) + "\n")
    (out / "fonts.json").write_text(json.dumps(export_fonts(repo), indent=2) + "\n")


if __name__ == "__main__":
    main()
