#!/usr/bin/env bash
# Render the game from the local player's eyes and print what the world says.
#
#   tools/shot.sh                        # 8 seconds in, to screenshots/bfh.png
#   tools/shot.sh 20 chase.png           # later, somewhere else
#   tools/shot.sh 9 tanks.png --tanks    # from a camera rather than the player's eyes
#
# Anything after the filename is passed through to the scene, which is how --bus,
# --stacks, --tanks and --chat are reached. They were unreachable through this script
# until the pass-through existed: every camera flag had to be run by hand through
# xvfb-run, so the shot that got taken was whichever one the wrapper could produce.
#
# xvfb-run because this needs a rendering context and the machines this runs on have
# no display. `--headless` is NOT a substitute: it gives a null renderer and saves a
# frame of nothing, which is worse than no screenshot because it looks like one.
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p screenshots
seconds="${1:-8}"
out="${2:-bfh.png}"
shift $(( $# < 2 ? $# : 2 ))
exec xvfb-run -a "${GODOT:-godot}" --path . --resolution 1280x720 \
    res://tools/shot.tscn -- "--seconds=$seconds" "--out=res://screenshots/$out" "$@"
