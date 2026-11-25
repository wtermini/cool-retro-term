#!/usr/bin/env python3
#
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
"""Checks an app's office desk MCP server and data file against the shared
format, so the Qt app and Cool Retro Term SE stay compatible (CI runs this
for both):

    python3 tests/office-desk/check.py <app binary> <path of office-desk.json>

It reads the version 1 and version 2 sample files here through the server,
makes changes, and checks what the app wrote. It replaces the data file, so
point it at a throwaway one.
"""

import json
import os
import shutil
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
COLORS = {"yellow", "pink", "green", "blue", "orange"}


def session(binary, calls):
    """Runs one MCP session; returns the tool results in order."""
    lines = [{"jsonrpc": "2.0", "id": 0, "method": "initialize",
              "params": {"protocolVersion": "2025-06-18", "capabilities": {}}},
             {"jsonrpc": "2.0", "method": "notifications/initialized"}]
    for i, (name, args) in enumerate(calls, 1):
        lines.append({"jsonrpc": "2.0", "id": i, "method": "tools/call", "params": {"name": name, "arguments": args}})
    out = subprocess.run([binary, "--mcp"], input="\n".join(json.dumps(l) for l in lines) + "\n",
                         capture_output=True, text=True, timeout=60).stdout
    replies = {m["id"]: m for m in map(json.loads, filter(None, out.splitlines()))}
    assert replies[0]["result"]["serverInfo"]["name"] == "cool-retro-term-office-desk", replies[0]
    results = []
    for i in range(1, len(calls) + 1):
        result = replies[i]["result"]
        text = result["content"][0]["text"]
        try:
            text = json.loads(text)
        except ValueError:
            pass
        results.append((result.get("isError", False), text))
    return results


def check_file(path):
    """The file as the apps write it: version 2, notes as a list."""
    with open(path, encoding="utf-8") as f:
        data = json.load(f)
    assert data["version"] == 2, data
    assert isinstance(data["notes"], list) and len(data["notes"]) <= 8
    for note in data["notes"]:
        assert set(note) == {"id", "text", "color"} and note["color"] in COLORS, note
    for event in data["events"]:
        assert set(event) == {"id", "date", "time", "title"}, event
    return data


def main():
    binary, path = sys.argv[1], sys.argv[2]
    os.makedirs(os.path.dirname(path), exist_ok=True)

    # Version 1: three fixed notes become a list, with their old names as ids.
    shutil.copy(os.path.join(HERE, "v1.json"), path)
    (_, desk), = session(binary, [("get_desk", {})])
    notes = desk["stickyNotes"]
    assert [n["id"] for n in notes] == ["monitor", "side", "wall"], notes
    assert notes[2]["text"] == "Version 1 wall note\nsecond line" and notes[0]["color"] == "blue", notes
    (_, events), = session(binary, [("list_calendar_events", {})])
    assert [e["id"] for e in events] == ["abc123"], events

    # Version 2: Unicode survives, bad values are cleaned up, events sorted.
    shutil.copy(os.path.join(HERE, "v2.json"), path)
    (_, desk), (_, events) = session(binary, [("get_desk", {}), ("list_calendar_events", {"from": "2030-01-01"})])
    notes = desk["stickyNotes"]
    assert notes[0] == {"id": "n1", "text": "Unicode: 日本語, emoji 🚀", "color": "orange"}, notes[0]
    assert notes[1]["color"] == "yellow" and notes[1]["text"] == "Unknown colour becomes yellow", notes[1]
    assert notes[2]["id"] != "N3!" and len(notes[2]["id"]) > 0, notes[2]
    assert [e["id"] for e in events] == ["e1", "e2"], events
    assert events[1]["title"] == "Review été — café ☕", events[1]

    # Changes, as an agent would make them; then the file must be version 2.
    results = session(binary, [
        ("add_sticky_note", {"text": "From the check", "color": "pink"}),
        ("update_sticky_note", {"id": "n1", "text": "Rewritten"}),
        ("delete_sticky_note", {"id": "n2"}),
        ("add_calendar_event", {"date": "2030-01-05", "time": "", "title": "All day"}),
        ("update_calendar_event", {"id": "e1", "time": "10:00"}),
        ("delete_calendar_event", {"id": "e2"}),
        ("add_calendar_event", {"date": "2030-02-29", "title": "Not a leap year"}),
        ("update_sticky_note", {"id": "n1", "color": "purple"}),
        ("delete_sticky_note", {"id": "missing"}),
    ])
    errors = [error for error, _ in results]
    assert errors == [False, False, False, False, False, False, True, True, True], results
    data = check_file(path)
    texts = [n["text"] for n in data["notes"]]
    assert texts[0] == "Rewritten" and "From the check" in texts and len(texts) == 3, texts
    assert [(e["id"], e["time"]) for e in data["events"]][:1] == [("e1", "10:00")], data["events"]

    # The length limit counts code points, the same in both apps: 300
    # rockets (2 UTF-16 units each) keep 280.
    (_, note), = session(binary, [("update_sticky_note", {"id": "n1", "text": "🚀" * 300})])
    assert note["text"] == "🚀" * 280, len(note["text"])

    # At most eight notes.
    results = session(binary, [("add_sticky_note", {"text": f"Extra {i}"}) for i in range(8)])
    assert sum(1 for error, _ in results if not error) == 5, results   # 3 + 5 = 8
    assert len(check_file(path)["notes"]) == 8
    print("office desk: data format and MCP server OK")


if __name__ == "__main__":
    main()
