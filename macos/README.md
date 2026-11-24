# Cool Retro Term for macOS (native)

A native macOS front end for cool-retro-term, written in Swift with AppKit and
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
open "build/Cool Retro Term.app"
```

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
change under `macos/` and uploads it as the `Cool-Retro-Term-macOS` artifact,
along with screenshots of a few profiles. The download is signed ad hoc, not
notarized, so macOS will refuse to open it the first time. After unzipping:

```sh
xattr -dr com.apple.quarantine "Cool Retro Term.app"
```

## Using it

- **View ▸ Profile** switches between the built-in profiles and your custom
  profiles from the Qt app. The choice is saved to the shared settings and
  applies to every window.
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
  Control-J do the same.)
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

`build-app.sh` puts the GPL text, SwiftTerm's license and
[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) in the app's
`Contents/Resources/Licenses`, next to the fonts and their licenses; Help ▸
Licenses shows them. If you distribute a build, the GPL also requires you to
offer the corresponding source code, such as a link to this repository at the
commit you built.

Three font folders inherited from the Qt app (Cozette, Fixedsys Excelsior and
Atari Classic, whose terms are in a PDF) don't include a plain license file;
THIRD_PARTY_NOTICES.md notes where their terms come from.

## Not done yet

- A settings window for editing profiles and individual effects. For now, edit
  them in the Qt app; this app picks up the changes.
- Line spacing and font width from the profiles (SwiftTerm doesn't support them).
- Window opacity.
- A confirmation before closing a window with a running process.
