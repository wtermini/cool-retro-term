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

## What's native

- Real macOS windows and **tabs** (Cmd-T, the tab bar's "+" button, Window ▸
  Merge All Windows), **full screen** (Ctrl-Cmd-F) and the standard menu bar.
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

- **View ▸ Profile** switches between the built-in profiles (the same ones as
  the Qt app). The choice is remembered and applies to every window.
- **View ▸ CRT Effects** (Option-Cmd-E) turns the effects off, leaving a plain,
  fast terminal in the profile's colours.
- **Cmd-Plus / Cmd-Minus / Cmd-0** change the text size.

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

## Not done yet

- A settings window for editing profiles and individual effects (the Qt app's
  settings dialog). Profiles can be picked from the menu.
- Custom profiles, importing profiles from the Qt app, and the system font list.
- Line spacing and font width from the profiles (SwiftTerm doesn't support them).
- Window opacity.
- A confirmation before closing a window with a running process.
