#!/bin/bash
# tour.sh init|start|click|skip|dismiss|reset|status|event <launch|workspace|navigate|resize|palette>
#
# The haus tour — the first-run tutor. One quiet pill on the RIGHT side of the
# bar walks the four moves (launch / navigate / resize / palette): no window,
# no focus steal, no key logging. Completion is detected from signals the rice
# already fires — the leader-mode scripts and aerospace-notify.sh call
# `tour.sh event <name>`, each guarded by a single `[ -f $STATE ]`, so an idle
# machine pays one stat per mode change and nothing else. We verify the
# RESULTING state (mode entered, workspace changed), never the keystroke.
#
# Steps are strictly sequential:
#   1a  tap caps (launch mode armed)          <- launch_mode.sh on
#   1b  press a letter (an app launches)      <- aerospace-notify.sh (workspace
#                                                changed; a letter that lands on
#                                                the CURRENT workspace won't fire
#                                                — click the pill to skip)
#   2   caps + arrow (navigate mode)          <- navigate_mode.sh on
#   3   caps + -/=   (resize mode)            <- resize_mode.sh on
#   4   ⌘Space, type tour                     <- the pounce "Haus Tour" command
#                                                (skipped when pounce is off)
#
# Left-click skips the current step (dormant: starts), right-click dismisses
# for good. Entry points: the dormant "new here?" hint on a fresh machine,
# `haus tour`, and the pounce command — which doubles as step 4's detection,
# so the palette finishes its own tutorial.
#
# State: $STATE holds the current step; $DONE present == completed or
# dismissed — it's what keeps the dormant hint from ever coming back. `reset`
# clears both and re-arms the hint.
#
# Concurrency: caps->letter can fire `launch` and `workspace` back to back as
# fire-and-forget processes, so every mutation runs under the same mkdir-lock
# trick launch_mode.sh uses. The "nice" flash sleeps WHILE holding the lock on
# purpose: a queued event blocks until the flash lands, then reads the settled
# step. The steal window (~5s) stays above the longest flash (4s).

export PATH="/run/current-system/sw/bin:/opt/homebrew/bin:/usr/bin:/bin:$PATH"

STATE_DIR="$HOME/.local/state/nebelhaus"
STATE="$STATE_DIR/tour"        # current step: 1a | 1b | 2 | 3 | 4
DONE="$STATE_DIR/tour-done"    # present == completed or dismissed
LOCK="/tmp/sketchybar_tour.lock"

source "$HOME/.config/sketchybar/colors.sh"
source "$HOME/.config/sketchybar/workspaces.sh"

# GENERATED gate (modules/sill/default.nix): TOUR_HAS_PALETTE=0 when pounce is
# off, which drops step 4 and makes it a three-step tour.
TOUR_HAS_PALETTE=1
[ -f "$HOME/.config/sketchybar/tour_config.sh" ] && source "$HOME/.config/sketchybar/tour_config.sh"
TOTAL=3; [ "$TOUR_HAS_PALETTE" = 1 ] && TOTAL=4

# fa-paw (U+F1B0) as raw UTF-8 bytes — /bin/bash is 3.2, whose printf has no
# \u/\U; \xHH works (same trick as launch_mode.sh).
PAW=$(printf '\xEF\x86\xB0')

# Step 1's letter comes from the roster (LAUNCHER_KEYS = 1 2 3 4 + app keys, in
# roster order), so the tour teaches YOUR first app, not a hardcoded t.
APP_KEY="${LAUNCHER_KEYS[4]:-t}"

acquire_lock() {
    local n=0
    until mkdir "$LOCK" 2>/dev/null; do
        sleep 0.05
        n=$((n + 1))
        [ $n -ge 100 ] && rmdir "$LOCK" 2>/dev/null   # ~5s: steal a crashed lock
    done
    trap 'rmdir "$LOCK" 2>/dev/null' EXIT
}

step() { cat "$STATE" 2>/dev/null; }

render() {
    local lbl
    case "$(step)" in
        1a) lbl="1/$TOTAL · tap ⇪ (Caps Lock)" ;;
        1b) lbl="1/$TOTAL · now press $APP_KEY — the letters are in the bar" ;;
        2)  lbl="2/$TOTAL · tap ⇪, then an arrow — ⎋ ends" ;;
        3)  lbl="3/$TOTAL · tap ⇪, then - or = — ⎋ ends" ;;
        4)  lbl="4/$TOTAL · press ⌘ Space, type tour, hit ↵" ;;
        *)  return ;;
    esac
    sketchybar --set tour drawing=on \
        background.color=$SURFACE0 icon="$PAW" icon.color=$PINK \
        label.color=$TEXT label="$lbl"
}

dormant() {
    sketchybar --set tour drawing=on \
        background.color=$MANTLE icon="$PAW" icon.color=$PINK \
        label.color=$SUBTEXT0 label="new here? click for a tour (right-click hides)"
}

hide() { sketchybar --set tour drawing=off; }

# A short colored beat between steps ("tap ⇪ then t… nice"). Sleeping while
# holding the lock is deliberate — see the concurrency note up top.
flash() { # flash <bg-color> <seconds> <label>
    sketchybar --set tour drawing=on \
        background.color=$1 icon="$PAW" icon.color=$BASE \
        label.color=$BASE label="$3"
    sleep "$2"
}

finish() {
    flash "$MAUVE" 4 "the house is yours $PAW — ⇪ / opens the cheatsheet"
    touch "$DONE"; rm -f "$STATE"
    hide
}

# Move past the current step. $1 = a "nice" line to flash; empty (a click-skip)
# flashes nothing — no praise for a move that didn't happen.
advance() {
    case "$(step)" in
        1a|1b) [ -n "$1" ] && flash "$GREEN" 2 "$1"; echo 2 > "$STATE" ;;
        2)     [ -n "$1" ] && flash "$GREEN" 2 "$1"; echo 3 > "$STATE" ;;
        3)     [ -n "$1" ] && flash "$GREEN" 2 "$1"
               if [ "$TOUR_HAS_PALETTE" = 1 ]; then echo 4 > "$STATE"; else finish; return; fi ;;
        4)     finish; return ;;
        *)     return ;;
    esac
    render
}

start() {
    # The item only exists when the tour is wired in (nebelhaus.tour.enable +
    # prowl + sill) — refuse cleanly instead of scribbling state nothing reads.
    if ! sketchybar --query tour >/dev/null 2>&1; then
        echo "tour: the bar has no tour item — it needs nebelhaus.tour.enable with prowl + sill on." >&2
        exit 1
    fi
    mkdir -p "$STATE_DIR"
    rm -f "$DONE"
    echo 1a > "$STATE"
    render
}

case "$1" in
    init)
        # Called by the generated tour_item.sh right after adding the item:
        # repaint whatever the last session left — a mid-tour step, done
        # (hidden), or the dormant first-run hint.
        acquire_lock
        if [ -f "$STATE" ]; then render
        elif [ -f "$DONE" ]; then hide
        else dormant; fi
        ;;
    start)   acquire_lock; start ;;
    reset)   acquire_lock; rm -f "$STATE" "$DONE"; dormant ;;
    skip)    acquire_lock; advance "" ;;
    dismiss) acquire_lock; touch "$DONE"; rm -f "$STATE"; hide ;;
    click)
        # $BUTTON is exported by sketchybar for click_scripts.
        acquire_lock
        if [ "${BUTTON:-left}" = "right" ]; then touch "$DONE"; rm -f "$STATE"; hide
        elif [ -f "$STATE" ]; then advance ""
        else start; fi
        ;;
    status)  step; [ -f "$STATE" ] || echo "idle$([ -f "$DONE" ] && echo ' (done)')" ;;
    event)
        # The live-detection funnel. Callers guard with [ -f $STATE ] — except
        # `palette`, which is also the tour's re-entry point (⌘Space → tour).
        case "$2" in
            launch)    acquire_lock; [ "$(step)" = 1a ] && { echo 1b > "$STATE"; render; } ;;
            workspace) acquire_lock; [ "$(step)" = 1b ] && advance "nice — that's the launcher" ;;
            navigate)  acquire_lock; [ "$(step)" = 2 ] && advance "nice — ⇧+arrow drags the window along" ;;
            resize)    acquire_lock; [ "$(step)" = 3 ] && advance "nice — it repeats till ⎋" ;;
            palette)
                acquire_lock
                case "$(step)" in
                    4)  advance "" ;;   # advancing past 4 IS the finale
                    "") start ;;        # no tour running — (re)start one
                    *)  render ;;       # mid-tour: just repaint
                esac
                ;;
            *) echo "usage: $0 event launch|workspace|navigate|resize|palette" >&2; exit 1 ;;
        esac
        ;;
    *) echo "usage: $0 init|start|click|skip|dismiss|reset|status|event <name>" >&2; exit 1 ;;
esac
