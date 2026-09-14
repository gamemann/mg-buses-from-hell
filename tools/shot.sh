#!/usr/bin/env bash
# Render the game from the local player's eyes and print what the world says.
#
#   tools/shot.sh                 # 8 seconds in, to screenshots/bfh.png
#   tools/shot.sh 20 chase.png    # later, somewhere else
#
# xvfb-run because this needs a rendering context and the machines this runs on have
# no display. `--headless` is NOT a substitute: it gives a null renderer and saves a
# frame of nothing, which is worse than no screenshot because it looks like one.
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p screenshots
seconds="${1:-8}"
out="${2:-bfh.png}"
exec xvfb-run -a "${GODOT:-godot}" --path . --resolution 1280x720 \
    res://tools/shot.tscn -- "--seconds=$seconds" "--out=res://screenshots/$out"
