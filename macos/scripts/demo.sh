#!/bin/sh
# Prints a sample screen for checking how the terminal renders: block art,
# box drawing, colours and the symbols CLI tools such as Claude Code use.
clear
printf '\n'
printf '  \033[38;5;173m▐▛███▜▌\033[0m   Cool Retro Term\n'
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
