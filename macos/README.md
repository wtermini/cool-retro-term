# Cool Retro Term SE

The native macOS edition of [cool-retro-term](https://github.com/Swordfish90/cool-retro-term),
written in Swift with AppKit and
Metal. It lives alongside the Qt app, which is unchanged and still builds for
Linux and macOS as before.

| | Qt app (`app/`) | Native app (`macos/`) |
|---|---|---|
| UI toolkit | Qt Quick | AppKit |
| Terminal emulation | qmltermwidget (Konsole) | [SwiftTerm](https://github.com/migueldeicaza/SwiftTerm) |
| CRT effects | Qt shaders | Metal ports of the same shaders |
| Profiles and fonts | built in | shared with the Qt app at build time |

## Shared settings with the Qt app

Both apps use the **same configuration**. The native app reads and writes
the Qt app's settings database (QtQuick LocalStorage, a SQLite file under
`~/Library/Application Support/cool-retro-term/cool-retro-term/QML/OfflineStorage/Databases/`):

- **Current profile**: whatever profile and effect settings you last used in
  the Qt app, including edits made in its settings dialog. Picking a profile
  here sets it for the Qt app too.
- **Custom profiles** saved in the Qt app appear under View ▸ Profile.
- **Text size** is the Qt app's font scaling (Cmd-Plus / Cmd-Minus change it
  in the same steps).
- **Custom command**: if the Qt app is set to run a custom command instead of
  the shell, so is this one.

Changes made in the Qt app are picked up when you switch back to this app.
Only the CRT Effects switch is specific to this app. Like two copies of the
Qt app, whichever app saves last wins if both change the same setting while
running.

## What's native

- Real macOS windows, **full screen** (Ctrl-Cmd-F) and the standard menu
  bar, with the app's own **tab bar** in the title bar area (see below).
- **Title bar proxy icon** for the shell's current directory (zsh on macOS
  reports it by default), and the window title the shell sets.
- **Option as Meta**, as expected in a terminal.
- **Services** menu, standard About panel, Dock reopen behaviour.
- Starts your **login shell** with a **UTF-8 locale**, even when launched from
  Finder or the Dock, so Unicode output (box drawing, Claude Code's symbols)
  isn't garbled.
- CRT effects run on the GPU with **Metal** and **pause when the window is
  hidden**, so background windows don't use battery. The app can run on the
  integrated GPU of dual-GPU Macs.
- **Retina** aware: smooth fonts render at full resolution, while the bitmap
  retro fonts are drawn at their native pixel size and scaled up, like the Qt
  app does.

## Building

Requires macOS 13 or later and Xcode 16 or later (for Swift 6 and SwiftTerm).

```sh
cd macos
./build-app.sh            # release build for this Mac's architecture
./build-app.sh --universal  # Apple silicon + Intel
open "build/Cool Retro Term SE.app"
```

CI builds with `--ci-hooks`, which makes the app honour a few `CRT_*`
environment variables used to take screenshots (pick a profile, type a demo
command, save the screen and quit). Normal builds leave them out, so nothing
in the environment can drive the app; the CI download is rebuilt without them.

`build-app.sh` exports the profiles and font table from the Qt sources
(`scripts/export-shared-data.py`), copies the bundled fonts, builds with
SwiftPM, assembles the `.app` bundle and signs it ad hoc so it runs locally.

For development, after running `build-app.sh` once:

```sh
swift run      # runs from the source tree, using macos/.build/resources
```

or open `Package.swift` in Xcode.

### Downloading a CI build

The **macOS native app** GitHub Actions workflow builds the app on every
change under `macos/` and uploads it as the `Cool-Retro-Term-SE-macOS` artifact,
along with screenshots of a few profiles. The download is signed ad hoc, not
notarized, so macOS will refuse to open it the first time. After unzipping:

```sh
xattr -dr com.apple.quarantine "Cool Retro Term SE.app"
```

## Using it

- **Settings** (Cool Retro Term SE ▸ Settings…, Cmd-Comma, or right-click ▸
  Settings…) is a standard Mac settings window with five panes:
  - *General*: Option as Meta, the Shift-/Control-Return new line keys,
    Secure Keyboard Entry, tab bar and resize options, and the custom shell
    command.
  - *Profiles*: choose, save, delete, import and export profiles; turn the
    CRT effects on or off; colours, brightness, contrast and opacity.
  - *Text*: font (bundled retro fonts or any monospaced font on your Mac),
    size, width, line spacing, cursor shape (solid block, underline or
    bar) and the blinking cursor. Both are also in the View menu, and the
    cursor stays solid when the window isn't focused. Programs that set
    their own cursor (such as vim's bar in insert mode) get exactly that
    until they ask for the default again or reset the terminal, and then
    your cursor comes back.
  - *Effects*: rasterization, bloom, burn-in, noise, jitter, glowing line,
    curvature, flicker, sync, RGB shift and the frame.
  - *Performance*: effects frame rate and texture, bloom and burn-in quality.

  Changes apply to every window as you make them and are shared with the Qt
  app, as its own settings dialog's are.

- **View ▸ Profile** switches between the built-in profiles and your custom
  profiles from the Qt app. The choice is saved to the shared settings and
  applies to every window.
- **View ▸ Office Mode** puts the terminal on the screen of a CRT monitor
  in a 3D room: an **80s Den** (wood panelling, shag carpet, a banker's lamp),
  a **90s Cubicle** (fabric partitions, fluorescent lights, sticky notes), a
  **2000s Office** (an LCD with a webcam, a whiteboard, a SYNERGY poster, a
  CD spindle) or **Frutiger Aero** (the 2000s as people remember them: a glass
  desk, a glossy white monitor with a glowing halo, an aquarium, bamboo,
  floating bubbles and a window onto a blue sky and a green hill).
  The terminal keeps working as usual on the monitor's screen, which gives
  off light in the profile's colour.
  - Pick the monitor in View ▸ Office Mode: a **Widescreen Monitor
    (16:10)**, a big, deep workstation CRT on a base plate (the default), or
    a **Standard Monitor (4:3)**.
  - Three views: **Close Up** (the screen fills most of the window), **At
    the Desk** and **Whole Room**. The camera glides between them.
  - **Sticky Notes** turns the notes on the monitor and walls on or off.
  - **Orbit When Idle**: after a while with no typing or mouse use (Never,
    or 1 to 30 minutes; 5 by default), the camera slowly swings back and
    forth around the monitor, like a screensaver, at a Slow, Normal or Fast
    pace. It stays inside the room, and the next key press or mouse
    movement glides it back. Program output (Claude Code at work, say)
    doesn't stop it.
  - With **View ▸ Office Mode ▸ Look Around** on, **Option-drag** looks
    around the room, **Option-scroll** or **pinch** zooms, and
    **Option-double-click** (or Reset View) goes back to the desk; the view
    also drifts gently and follows the pointer a little. Turn it off for a
    fixed view.
  - The room is drawn in 3D with SceneKit on Metal. Turn off **3D Room** (or
    on a Mac without Metal) for a picture of the same room instead, with the
    terminal over the monitor's screen.
  - The terminal takes the monitor's shape (16:10 or 4:3) in office mode,
    and the CRT effects are always on.
  - The 3D room is drawn at the effects frame rate, and stops with the
    effects when the window is hidden.
  - Also in Settings ▸ General, and shared with the Qt app (View ▸ Office
    Mode, or Settings ▸ Advanced), which builds the same rooms with Qt
    Quick 3D.
- **View ▸ CRT Effects** (Option-Cmd-E) turns the effects off, leaving a plain,
  fast terminal in the profile's colours.
- **Cmd-Plus / Cmd-Minus / Cmd-0** change the text size.
- **Tabs**: Cmd-T opens one, Cmd-W closes one (Shift-Cmd-W closes the
  window), Cmd-1 to Cmd-9 and Shift-Cmd-[ / ] switch between them. In the tab
  bar, click "+" or double-click empty space for a new tab, drag tabs to
  reorder them, middle-click or use the × to close, and right-click for a
  menu. The bar appears once a window has two tabs, or always with View ▸
  Always Show Tab Bar.
- **Shift-Return** and **Control-Return** insert a new line in programs that
  support it, such as Claude Code, instead of submitting. (Option-Return and
  Control-J do the same.) When a program turns on the extended (kitty)
  keyboard protocol, as Claude Code does, they're sent in that protocol's
  encoding. Control-Return never opens the context menu in the terminal.
- **Tab names** follow the title the running program sets: the shell's
  current command or directory, or Claude Code's session name.
  **Double-click a tab** (or Shell ▸ Rename Tab…, Shift-Cmd-R) to give it a
  fixed name; Return saves, Escape cancels, and an empty name goes back to
  the automatic title.
- **Tab colours**: right-click a tab, or Shell ▸ Tab Color (Custom… for any
  colour). The whole tab is filled with the colour, brightest when selected,
  and the CRT bezel is tinted to match. Programs and shell scripts can also
  set it with the common OSC 6 escape sequence, for example to turn a tab
  red while you're on a production server:

  ```sh
  printf '\e]6;1;bg;red;brightness;220\a\e]6;1;bg;green;brightness;40\a\e]6;1;bg;blue;brightness;40\a'
  printf '\e]6;1;bg;*;default\a'   # reset
  ```

  A colour picked from the menu always wins over one set by a program.
  **Custom…** (in the tab's right-click menu and Shell ▸ Tab Color) picks
  any colour.

## The office desk: sticky notes, calendar and an MCP server

In office mode's 3D rooms, the sticky notes and the wall calendar are live:
the calendar shows this month with today circled, marks the days with events
and lists the next few; each note shows what's written on it. There can be up
to eight notes; they fill the monitor's bezel, its sides, the wall and the
desk in turn.

- **In the app**: View ▸ Office Mode ▸ Edit Notes and Calendar… adds,
  rewrites, recolours and deletes notes, and adds, changes and deletes
  events. In the room, double-click a note to edit it, or a day on the
  calendar to add an event that day.
- **For agents**: both apps include an MCP server for the desk. Register it
  with Claude Code (View ▸ Office Mode ▸ Copy Agent (MCP) Setup Command copies
  this line for you):

  ```sh
  claude mcp add office-desk -- "/Applications/Cool Retro Term SE.app/Contents/MacOS/CoolRetroTerm" --mcp
  # or, for the Qt app:
  claude mcp add office-desk -- /path/to/cool-retro-term --mcp
  ```

  Its tools are `get_desk`, `add_sticky_note`, `update_sticky_note`,
  `delete_sticky_note`, `list_calendar_events`, `add_calendar_event`,
  `update_calendar_event` and `delete_calendar_event`.

Everything is kept in one file, `office-desk.json`, in the app's data folder
(`~/Library/Application Support/cool-retro-term/cool-retro-term/` on macOS,
`~/.local/share/cool-retro-term/cool-retro-term/` on Linux), shared by both
apps and both servers, so a change made anywhere shows up everywhere straight
away. Both apps read and write it the same way (UTF-8 JSON, version 2; files
from the first version, with three fixed notes, are converted), take a lock
(`office-desk.lock`) while changing it so the apps and agents don't
overwrite each other, and count length limits in Unicode code points.
`tests/office-desk/check.py`, run by CI against both apps, checks this.

The server talks only over stdin/stdout (no network), touches only that file,
and accepts only plain text within length limits (280 characters per note,
120 per event title), real dates and HH:MM times, up to 8 notes and 500
events. The 2D office pictures show the notes and calendar as drawn, not
live.

## Efficiency

Both apps are built to stay light when nothing is happening:

- The effects always run while a window can be seen, and stop while it's
  minimised or completely hidden.
- **Pause effects when idle** (optional, off by default, in Settings ▸
  Performance and the Qt app's Advanced settings): a few seconds after the
  last output or key press, the effects stop animating and nothing is
  redrawn until something happens. A blinking cursor keeps blinking.
- The effects animate at the chosen frame rate (20 fps by default), while
  text changes are still drawn straight away.
- **Low Power Mode**: Cool Retro Term SE runs the effects at 12 fps.
- **Apple silicon**: the terminal is drawn straight into memory the GPU reads
  (unified memory), with no copy, and SwiftTerm's own view isn't redrawn
  underneath the CRT image.

## How it works

`CRTTerminalView` puts SwiftTerm's terminal view under a Metal view. SwiftTerm
draws the terminal in white on black as usual. Whenever its contents change,
the terminal is captured into a texture, and `CRTRenderer` runs it through the
shaders in `Shaders/CRT.metal`:

1. **Burn-in**: accumulates fading afterimages of recent text.
2. **Dynamic pass**: static noise, jitter, horizontal sync wobble, the
   scrolling glow line, scanline/pixel rasterization, flicker, and mapping
   brightness to the profile's colours.
3. **Bloom**: a quarter-resolution blur of the result.
4. **Final pass**: screen curvature, bezel reflections, RGB shift, bloom,
   brightness and the bezel itself.

Mouse events are passed to the terminal after applying the same curvature, so
selecting text lands on the characters under the pointer.

The shaders are compiled when the app starts, so building needs no Metal
toolchain.

## Security

Anything printed in a terminal can contain escape sequences, including
output from a file you `cat`, a page you `curl` or a remote machine over ssh.
On top of SwiftTerm's defaults, this app:

- **refuses clipboard reads** requested by programs (OSC 52), which would
  otherwise let any output silently read what you last copied. Programs can
  still *set* the clipboard, as vim and tmux do;
- **checks Cmd-clicked links**: web and mail links open normally, plain
  documents (text, source code, images, PDFs, media) open in their app;
  applications, scripts and other files are only shown in Finder; and other
  kinds of links ask first and show where they really point;
- offers **Secure Keyboard Entry** (in the app menu, as in Terminal.app),
  which stops other apps from reading your keystrokes while this one is in
  front;
- runs your shell as you, with your normal environment and no extra
  privileges. Like any terminal, the app isn't sandboxed, since it has to be
  able to run anything you ask it to.

SwiftTerm is pinned to the exact commit of release 1.20.0 in `Package.swift`.

## Licenses

The native app is part of cool-retro-term and, like it, is licensed under the
GNU GPL version 3 or later; every source file carries the same license header
as the Qt app's. The Metal shaders are ports of the Qt app's shaders and keep
their original copyright notice.

Third-party code and assets keep their own licenses, all compatible with
GPL-3.0:

- [SwiftTerm](https://github.com/migueldeicaza/SwiftTerm), MIT License.
- The bundled fonts, unmodified and each with its license file (SIL OFL,
  MIT, CC BY-SA 4.0, Kreative free use license and others).

The office mode rooms and their textures are original to this project:
`scripts/generate-office-scenes.py` builds them from simple shapes,
gradients and noise, and they're covered by the same GPL as the rest of the
code.

`build-app.sh` puts the GPL text, SwiftTerm's license and
[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) in the app's
`Contents/Resources/Licenses`, next to the fonts and their licenses; Help ▸
Licenses shows them. If you distribute a build, the GPL also requires you to
offer the corresponding source code, such as a link to this repository at the
commit you built.

Three font folders inherited from the Qt app (Cozette, Fixedsys Excelsior and
Atari Classic, whose terms are in a PDF) don't include a plain license file;
THIRD_PARTY_NOTICES.md notes where their terms come from.

## Parity with the Qt app

Everything in the Qt app's settings dialog, menus and command line has a
counterpart here:

| Qt app | Native app |
|---|---|
| Profiles: load, save, remove, import, export | Settings ▸ Appearance (same JSON file format) and View ▸ Profile |
| Brightness, contrast, margin, radius, frame size, opacity | Settings ▸ Appearance / Effects |
| Font source (bundled or system), name, scaling, width, line spacing | Settings ▸ Appearance ▸ Text |
| Font, background and frame colours; chroma and saturation | Settings ▸ Appearance ▸ Colours |
| Every effect (bloom, burn-in, noise, jitter, glow line, curvature, ambient light, flicker, sync, RGB shift, frame shininess, rasterization) | Settings ▸ Effects |
| Custom command instead of the shell; blinking cursor | Settings ▸ General / Appearance |
| Effects FPS, texture, bloom and burn-in quality | Settings ▸ General ▸ Performance |
| Terminal size shown while resizing | Same, can be turned off in Settings ▸ General |
| Right-click menu (copy, paste, new tab/window, profiles, settings, full screen, about) | Same |
| New window/tab, close tab, zoom in/out, Cmd-1…9, full screen | Same shortcuts |
| `--default-settings`, `--workdir`, `-e`, `-p/--profile`, `--fullscreen`, `-h`, `-v` | Same options (run the binary inside the app bundle) |
| Office mode (View ▸ Office Mode, Settings ▸ Advanced) | View ▸ Office Mode, Settings ▸ General |
| Show menu bar | Not applicable on macOS (the menu bar is always there) |

## Not done yet

- A confirmation before closing a window with a running process.
- Tabs and their names and colours aren't restored after quitting.
