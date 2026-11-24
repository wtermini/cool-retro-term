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

Apply it before building:

    git submodule update --init
    git -C qmltermwidget apply ../patches/qmltermwidget-draw-block-elements.patch
