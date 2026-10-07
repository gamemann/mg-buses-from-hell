#!/usr/bin/env bash
#
# game.sh -- play, host and test this game with one command each.
#
#   ./game.sh                      play it offline, in a window
#   ./game.sh play [-- ARGS]       the same; ARGS go to the game
#   ./game.sh online               run a local server plus the browser client, print the link
#   ./game.sh online down          stop it again
#   ./game.sh server               run a local dedicated server only (Ctrl+C stops it)
#   ./game.sh server check         start the server, load the game, stop; exit 0 if it worked
#   ./game.sh server -- ARGS       ARGS go to dot-server-deploy's ./server (e.g. -- --port 7000)
#   ./game.sh test                 parse every script, then run every test suite
#   ./game.sh test NAME...         run only these suites (e.g. ./game.sh test headless_net)
#   ./game.sh suites               list the test suites
#   ./game.sh shot [ARGS]          save a screenshot to screenshots/ (tools/shot.sh or tools/screenshot.sh)
#
# Options (before the command):
#   --godot PATH     the Godot 4.7 binary to use (default: $GODOT, then godot on PATH)
#   --timeout SEC    the longest one test suite may run (default 900)
#   --no-parse       skip the parse pass in `test`
#
# `online` and `server` use dot-server-deploy, found next to this repository (or at
# $DOT_SERVER_DEPLOY). dot-bootstrap puts it there. Both rebuild this game's pack first, so
# what you play is what is on disk now.
#
# The same script is in every game repository; only the settings below differ.

# --- This game ------------------------------------------------------------------
# PACK is the game's id in dot-server-deploy (empty if it has no server), EXTRA_PACKS
# are other packs it needs as id:repository pairs, and SUITES are the scenes in
# examples/ that test it.
GAME_NAME="Buses From Hell"
PACK="buses"
EXTRA_PACKS=""
SUITES="headless_run headless_net dedicated"
# --------------------------------------------------------------------------------

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT" || exit 1

GODOT="${GODOT:-godot}"
TIMEOUT=900
PARSE=1
RED=$'\033[31m'; GRN=$'\033[32m'; YLW=$'\033[33m'; OFF=$'\033[0m'
CR=$'\r\033[K'
[ -t 1 ] || { RED=""; GRN=""; YLW=""; OFF=""; CR=""; }

die() { printf '%s%s%s\n' "$RED" "$1" "$OFF" >&2; exit "${2:-1}"; }
usage() { sed -n '3,24p' "$ROOT/$(basename "${BASH_SOURCE[0]}")" | sed 's/^# \{0,1\}//'; }

while [ $# -gt 0 ]; do
    case "$1" in
        --godot) GODOT="${2:?--godot needs a path}"; shift 2 ;;
        --godot=*) GODOT="${1#*=}"; shift ;;
        --timeout) TIMEOUT="${2:?--timeout needs seconds}"; shift 2 ;;
        --timeout=*) TIMEOUT="${1#*=}"; shift ;;
        --no-parse) PARSE=0; shift ;;
        -h|--help|help) usage; exit 0 ;;
        *) break ;;
    esac
done

command -v "$GODOT" >/dev/null 2>&1 || die "Godot not found: '$GODOT'. Install Godot 4.7 or pass --godot PATH." 2

cmd="${1:-play}"
[ $# -gt 0 ] && shift

# The addons are links that dot-bootstrap makes. Without them nothing parses, and the
# errors read like a broken game rather than a missing step.
check_addons() {
    local missing=""
    while read -r name; do
        [ -e "addons/$name/plugin.cfg" ] || [ -d "addons/$name" ] || missing="$missing $name"
    done < <(sed -n 's|^/addons/\([^/]*\)/\{0,1\}$|\1|p' .gitignore 2>/dev/null)
    [ -z "$missing" ] || die "Missing addons:$missing
Run dot-bootstrap first: https://github.com/modcommunity/dot-bootstrap" 2
}

deploy_dir() {
    local dir="${DOT_SERVER_DEPLOY:-$ROOT/../dot-server-deploy}"
    [ -x "$dir/server" ] || die "dot-server-deploy not found at $dir (run its ./setup.sh, or set DOT_SERVER_DEPLOY)." 2
    (cd "$dir" && pwd)
}

# Rebuild this game's pack, and the packs it needs, from the checkouts on disk.
pack_all() {
    [ -n "$PACK" ] || die "$GAME_NAME has no server pack." 2
    local deploy repo id pair
    deploy="$(deploy_dir)"
    for pair in $EXTRA_PACKS; do
        id="${pair%%:*}"; repo="${pair#*:}"
        echo "packing $id"
        (cd "$deploy" && ./server pack "$id" --source "$ROOT/../$repo") >/dev/null || die "could not pack $id"
    done
    "$GODOT" --headless --path . --import >/dev/null 2>&1
    echo "packing $PACK"
    (cd "$deploy" && ./server pack "$PACK" --source "$ROOT") >/dev/null || die "could not pack $PACK"
}

run_suite() {
    local scene="$1" log out status summary
    [ -f "examples/$scene.tscn" ] || { printf '  %s??%s   %s: no examples/%s.tscn\n' "$YLW" "$OFF" "$scene" "$scene"; return 1; }
    mkdir -p .godot/test-logs
    log=".godot/test-logs/$scene.log"
    [ -t 1 ] && printf '  ..   %s' "$scene"
    timeout "$TIMEOUT" "$GODOT" --headless --path . "res://examples/$scene.tscn" >"$log" 2>&1
    status=$?
    summary="$(grep -Eo '[0-9]+ (passed|checks), [0-9]+ failed' "$log" | tail -1)"
    if [ "$status" -eq 124 ]; then
        out="did not finish within ${TIMEOUT}s"
    elif [ "$status" -ne 0 ]; then
        out="exited $status"
    elif grep -qE 'SCRIPT ERROR|Parse Error' "$log"; then
        # A script error aborts one test, not the run, so the suite can still exit 0.
        out="script error in the output"
    else
        printf '%s  %sok%s   %s  %s\n' "$CR" "$GRN" "$OFF" "$scene" "$summary"
        return 0
    fi
    printf '%s  %sFAIL%s %s: %s  %s\n' "$CR" "$RED" "$OFF" "$scene" "$out" "$summary"
    grep -E 'FAIL|SCRIPT ERROR|Parse Error|ERROR' "$log" | head -15 | sed 's/^/       /'
    printf '       full log: %s\n' "$log"
    return 1
}

do_test() {
    check_addons
    local fails=0 f out
    echo "importing"
    timeout 600 "$GODOT" --headless --path . --import >/dev/null 2>&1

    if [ "$PARSE" = 1 ] && [ $# -eq 0 ]; then
        echo "parsing every script"
        while read -r f; do
            out="$(timeout 120 "$GODOT" --headless --path . --check-only --script "res://$f" 2>&1 \
                | grep -Ev '^(Godot Engine v|$)' \
                | grep -Eiv 'ObjectDB instances( were)? leaked|resources still in use|Pages in use exist at exit|at: (cleanup|clear|~PagedAllocator)|Text-based project')"
            if [ -n "$out" ]; then
                printf '  %sFAIL%s %s\n%s\n' "$RED" "$OFF" "$f" "$out"
                fails=$((fails + 1))
            fi
        done < <(git ls-files '*.gd' 2>/dev/null || find . -name '*.gd' -not -path './.godot/*' -not -path './addons/*' | sed 's|^\./||')
        [ "$fails" -eq 0 ] && printf '  %sok%s   every script parses\n' "$GRN" "$OFF"
    fi

    echo "running the suites"
    local scene
    for scene in ${*:-$SUITES}; do
        run_suite "${scene%.tscn}" || fails=$((fails + 1))
    done

    echo
    [ "$fails" -eq 0 ] && { printf '%sall passed%s\n' "$GRN" "$OFF"; return 0; }
    printf '%s%d failed%s\n' "$RED" "$fails" "$OFF"
    return 1
}

case "$cmd" in
    play)
        check_addons
        [ "${1:-}" = "--" ] && shift
        exec "$GODOT" --path . -- "$@"
        ;;
    online)
        if [ "${1:-}" = "down" ]; then
            exec "$(deploy_dir)/play.sh" down
        fi
        case "${1:-}" in ""|-*) ;; *) PACK="$1"; shift ;; esac
        check_addons
        pack_all
        exec "$(deploy_dir)/play.sh" "$PACK"
        ;;
    server)
        sub="run"
        case "${1:-}" in run|check|config) sub="$1"; shift ;; esac
        check_addons
        pack_all
        [ "${1:-}" = "--" ] && shift
        cd "$(deploy_dir)" || exit 1
        exec ./server "$sub" --game "$PACK" "$@"
        ;;
    test)
        do_test "$@"
        ;;
    suites)
        printf '%s\n' $SUITES
        ;;
    shot)
        for tool in tools/shot.sh tools/screenshot.sh; do
            [ -x "$tool" ] || continue
            if [ "${1:-}" = "--help" ] || [ "${1:-}" = "-h" ]; then
                # The tool's own header comment is its usage.
                sed -n '2,/^[^#]/p' "$tool" | sed '$d' | sed 's/^# \{0,1\}//'
                exit 0
            fi
            exec "$tool" "$@"
        done
        die "$GAME_NAME has no screenshot tool." 2
        ;;
    *)
        usage
        exit 2
        ;;
esac
