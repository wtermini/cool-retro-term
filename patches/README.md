# Patches for the qmltermwidget submodule

## qmltermwidget-draw-block-elements.patch

Draws Unicode block elements (U+2580–U+259F: `▀ ▄ █ ▌ ▐ ░ ▒ ▓ ▖ ▗ ▘ ▙ ▚ ▛ ▜ ▝ ▞ ▟`
and the 1/8 blocks) as filled rectangles covering the whole cell, the same way
box-drawing characters are already drawn, instead of using the font's glyphs.

Most of the bundled retro fonts don't contain these glyphs (or draw them
smaller than the cell once line spacing is added), so logos and graphics built
from them, such as the Claude Code logo `▐▛███▜▌`, come out misaligned with gaps
between rows.

It also draws the line markers Claude Code uses, `⏺` (U+23FA) and `⎿`
(U+23BF), since only Cozette, Iosevka and unscii-16 include them. With the
other fonts, Qt substitutes a glyph from whatever system font has one, which
looks out of place (on macOS it can come out looking like a stray letter).

The patch changes files in qmltermwidget, which is licensed under the GNU
GPL version 2 or later. The changes are under the same license.

## qmltermwidget-cursor-shape.patch

Exposes the cursor shape to QML as `QMLTermWidget.cursorShape` (0 block,
1 underline, 2 bar), for the Cursor Shape setting.

## qmltermwidget-session-signals.patch

Adds signals to `QMLTermSession`:

- `outputReceived()`, emitted when the program writes output (without the
  data). Used by the optional "pause effects when idle".
- `programCursorChanged(shape, blinking)` and `programCursorReset()`: a
  program set its own cursor (DECSCUSR 1-6), or asked for the default
  (DECSCUSR 0) / reset the terminal. Previously these were parsed but never
  reached the display, and DECSCUSR 0 meant a blinking block rather than the
  user's cursor.
- `tabColorRequested(spec)`, described below.

It reports the OSC 6 tab colour escape sequence (`ESC ] 6 ; 1 ; bg ; red ;
brightness ; N BEL`, and `... ; * ; default` to reset) to QML, as the
`tabColorRequested(spec)` signal on `QMLTermSession`, so programs can colour
their tab, as they can in Cool Retro Term SE. Each sequence is passed on
straight away, because one colour is sent as three sequences in a row.

## Applying

`cool-retro-term.pro` applies every `qmltermwidget-*.patch` here when you run
qmake, skipping any that are already applied, so a normal build needs no extra
step:

    git submodule update --init
    qmake && make
