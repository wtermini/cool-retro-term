#!/usr/bin/env python3
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
