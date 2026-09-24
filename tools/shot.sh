#!/usr/bin/env bash
# Render the game from the local player's eyes and print what the world says.
#
#   tools/shot.sh                        # 8 seconds in, to screenshots/bfh.png
#   tools/shot.sh 20 chase.png           # later, somewhere else
#   tools/shot.sh 9 tanks.png --tanks    # from a camera rather than the player's eyes
#   tools/shot.sh 9 scaffold.png --scaffold   # the scaffold, from the end a runner climbs
#   tools/shot.sh 9 ramp.png --ramp           # the ramp, from the side
#   tools/shot.sh 9 beacon.png --beacon       # an admin's beacon: the runner's ring, the bus's column
#   tools/shot.sh 9 beacon_bus.png --beacon --bus   # the beacon round a driver's bus
#   tools/shot.sh 9 blind.png --blind         # an admin's blind, through the HUD
#   tools/shot.sh 6 net.png --net             # a CONNECTED client watching another runner:
#                                             # four consecutive frames and a jitter probe
#   tools/shot.sh 6 net.png --net --no-interp # the same with the client's interpolation off
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
# `--net` is a different scene rather than a flag inside shot.gd, because it is a
# different program: a server and a client in one process over a loopback, where shot.gd
# is the offline client as a player runs it.
scene=res://tools/shot.tscn
for arg in "$@"; do
  [ "$arg" = "--net" ] && scene=res://tools/net_shot.tscn
done
exec xvfb-run -a "${GODOT:-godot}" --path . --resolution 1280x720 \
    "$scene" -- "--seconds=$seconds" "--out=res://screenshots/$out" "$@"
