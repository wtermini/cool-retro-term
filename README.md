# cool-retro-term

|> Default Amber|C:\ IBM DOS|$ Default Green|
|---|---|---|
|![Default Amber Cool Retro Term](https://user-images.githubusercontent.com/121322/32070717-16708784-ba42-11e7-8572-a8fcc10d7f7d.gif)|![IBM DOS](https://user-images.githubusercontent.com/121322/32070716-16567e5c-ba42-11e7-9e64-ba96dfe9b64d.gif)|![Default Green Cool Retro Term](https://user-images.githubusercontent.com/121322/32070715-163a1c94-ba42-11e7-80bb-41fbf10fc634.gif)|

## Description
cool-retro-term is a terminal emulator which mimics the look and feel of the old cathode tube screens.
It has been designed to be eye-candy, customizable, and reasonably lightweight.

It uses the QML port of qtermwidget (Konsole): https://github.com/Swordfish90/qmltermwidget.

This terminal emulator works under Linux and macOS and requires Qt6.

Settings such as colors, fonts, and effects can be accessed via context menu.

## Screenshots
![Image](<https://i.imgur.com/TNumkDn.png>)
![Image](<https://i.imgur.com/hfjWOM4.png>)
![Image](<https://i.imgur.com/GYRDPzJ.jpg>)

## Install

If you want to get a hold of the latest version, just go to the Releases page and grab the latest AppImage (Linux) or dmg (macOS).

Alternatively, most distributions such as Ubuntu, Fedora or Arch already package cool-retro-term in their official repositories.

## Office mode

View ▸ Office Mode puts the terminal on the screen of a CRT monitor in a 3D room, an **80s Den** or a **90s Cubicle**, on a widescreen (16:10) or standard (4:3) CRT, drawn on the GPU (Qt Quick 3D on OpenGL or Metal here, SceneKit on Metal in Cool Retro Term SE). Pick the view (close up, at the desk or the whole room) and turn the sticky notes on or off in the same menu. With **Look Around** on, Option/Alt-drag looks around, Option/Alt-scroll zooms and Option/Alt-double-click goes back to the desk. Turn off **3D Room**, or run without Qt Quick 3D or a GPU, and you get a picture of the same room instead. The rooms are original, built by [`scripts/generate-office-scenes.py`](scripts/generate-office-scenes.py) (the pictures are rendered from them by `scripts/render-office-pictures.sh`), and the settings are shared between the two apps.

## The office desk: sticky notes, calendar and an MCP server

In office mode's 3D rooms, the three sticky notes (on the monitor, on its
side and on the wall) and the wall calendar are live: the calendar shows this
month with today circled, marks the days with events and lists the next
few; the notes show whatever is written on them.

- **Edit them yourself**: View ▸ Office Mode ▸ Edit Notes and Calendar…, or
  double-click a note or the calendar in the room.
- **Let an agent use them**: both apps include a small MCP server that reads
  and writes the desk. Register it with Claude Code (View ▸ Office Mode ▸
  Copy Agent (MCP) Setup Command copies this for you):

  ```sh
  claude mcp add office-desk -- "/Applications/Cool Retro Term SE.app/Contents/MacOS/CoolRetroTerm" --mcp
  # or, for the Qt app:
  claude mcp add office-desk -- /path/to/cool-retro-term --mcp
  ```

  Its tools are `get_desk`, `set_sticky_note`, `list_calendar_events`,
  `add_calendar_event`, `update_calendar_event` and `delete_calendar_event`.

Everything is kept in `office-desk.json` in the app's data folder
(`~/Library/Application Support/cool-retro-term/cool-retro-term/` on macOS,
`~/.local/share/cool-retro-term/cool-retro-term/` on Linux), shared by both
apps and the server, so a change made anywhere shows up everywhere straight
away. The server talks only over stdin/stdout (no network), touches only that
file, and accepts only plain text within length limits, real dates and
HH:MM times. The 2D office pictures show the notes and calendar as drawn,
not live.

## Keeping up with the original

A GitHub Actions workflow (`upstream-drift.yml`) checks once a month whether [Swordfish90/cool-retro-term](https://github.com/Swordfish90/cool-retro-term)'s `master` has commits this fork doesn't, and opens an issue listing them (labelled `bug` and `upstream-drift`).

## Cool Retro Term SE (native macOS app)

There is also a native macOS edition, **Cool Retro Term SE**, in [`macos/`](macos/README.md), built with AppKit, Metal and SwiftTerm. It shares the profiles and fonts with the Qt app, which is unchanged.

## Building

Check out the wiki and follow the instructions on how to build it on [Linux](https://github.com/Swordfish90/cool-retro-term/wiki/Build-Instructions-(Linux)) and [macOS](https://github.com/Swordfish90/cool-retro-term/wiki/Build-Instructions-(macOS)).
