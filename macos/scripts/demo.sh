#!/bin/sh
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
# Prints a sample screen for checking how the terminal renders: block art,
# box drawing, colours and the symbols CLI tools such as Claude Code use.
clear
printf '\n'
printf '  \033[38;5;173m▐▛███▜▌\033[0m   Cool Retro Term SE\n'
printf ' \033[38;5;173m▝▜█████▛▘\033[0m  native macOS build\n'
printf '   \033[38;5;173m▘▘ ▝▝\033[0m\n\n'
printf ' ⏺ Read 3 files\n'
printf '   ⎿  done\n\n'
printf ' ╭────────────────────────────╮\n'
printf ' │ \033[1mbold\033[0m  \033[4munderline\033[0m  \033[7mreverse\033[0m │\n'
printf ' ╰────────────────────────────╯\n\n'
for c in 31 32 33 34 35 36 37; do printf ' \033[%sm██\033[0m' "$c"; done
printf '\n blocks: ▀▄█▌▐░▒▓▖▗▘▙▚▛▜▝▞▟\n\n'
ls -la / | head -8
