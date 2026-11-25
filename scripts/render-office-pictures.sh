#!/bin/sh
# Renders office mode's 2D fallback pictures (app/qml/office/office-*.jpg)
# from the 3D rooms, seen straight on, with Qt Quick 3D.
# Run scripts/generate-office-scenes.py first. Needs Qt 6 with Qt Quick 3D,
# Python with Pillow, and a display (or xvfb-run, used when there's none).
set -e
REPO=$(cd "$(dirname "$0")/.." && pwd)
QML=${QML:-$(command -v qml || echo /usr/lib/qt6/bin/qml)}
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
export QML_XHR_ALLOW_FILE_READ=1
if [ -z "$DISPLAY" ] && [ "$(uname)" != Darwin ] && command -v xvfb-run > /dev/null; then
    RUN="xvfb-run -a -s \"-screen 0 2600x1700x24\""
fi
# Some Qt versions crash on exit after rendering, so check for the output
# instead of the exit status.
eval "${RUN:-}" '"$QML" "$REPO/scripts/render-office-pictures.qml" -- "$TMP"' || true
for scene in 80s-standard 80s-wide 90s-standard 90s-wide; do
    [ -f "$TMP/office-$scene.png" ] || { echo "rendering office-$scene failed" >&2; exit 1; }
    python3 -c "
import sys
from PIL import Image
Image.open(sys.argv[1]).convert('RGB').resize((2400, 1500), Image.LANCZOS).save(sys.argv[2], quality=85, optimize=True, progressive=True)
" "$TMP/office-$scene.png" "$REPO/app/qml/office/office-$scene.jpg"
    echo "wrote app/qml/office/office-$scene.jpg"
done
