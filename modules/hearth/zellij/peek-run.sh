#!/bin/bash
# peek-run.sh — runs INSIDE the peek ghostty instance (spawned by peek.sh).
#
# Keeps the peek window alive across yazi sessions: when yazi quits (q/Esc),
# the window is macOS-hidden instead of torn down, and this script parks on a
# fifo waiting for the next summon. peek.sh then just writes a directory to
# the fifo and unhides the window — no window creation, no aerospace event,
# no repositioning, so summoning is instant and visually seamless.

set -u
export PATH="/etc/profiles/per-user/$USER/bin:/run/current-system/sw/bin:$PATH"

# macOS `open` forwards the caller's environment, so the zellij pane that ran
# peek.sh leaks $ZELLIJ & co. into this instance — making yazi and
# image-preview.sh believe they're inside zellij and downgrade crisp kitty
# graphics to block art. This window is raw ghostty; scrub the lie.
unset ZELLIJ ZELLIJ_SESSION_NAME ZELLIJ_PANE_ID

FIFO="$HOME/.cache/peek.fifo"
PIDFILE="$HOME/.cache/peek.pid"

# Find the ghostty instance that owns our window. Ghostty runs its command
# under a `login` wrapper, so $PPID is NOT the app — walk the ancestor chain.
GPID=""
p=$PPID
while [ "${p:-1}" -gt 1 ]; do
    case "$(ps -o comm= -p "$p" 2>/dev/null)" in
        *[Gg]hostty*) GPID=$p; break ;;
    esac
    p=$(ps -o ppid= -p "$p" 2>/dev/null | tr -d ' ')
    [ -n "$p" ] || break
done
[ -n "$GPID" ] || GPID=0 # peek.sh's kill -0 check then forces a respawn

echo "$GPID $$" > "$PIDFILE"
# The window closing (cmd+w / instance quit) HUPs us: clean up AND die —
# a bare cleanup trap would leave this script running as an orphan.
trap 'rm -f "$PIDFILE"' EXIT
trap 'exit 0' HUP INT TERM

[ -p "$FIFO" ] || { rm -f "$FIFO"; mkfifo "$FIFO"; }

dir="$PWD"
while :; do
    [ -d "$dir" ] || dir="$HOME"
    yazi "$dir"
    # yazi quit → minimize our window; everything stays warm for the next
    # summon. (Minimize, not app-hide: NSRunningApplication.hide() and System
    # Events' `visible` both silently refuse to hide these open -na spawned
    # ghostty instances; AXMinimized works, animates natively, and macOS
    # hands focus back to the previous app by itself.)
    osascript -e "tell application \"System Events\" to tell (first process whose unix id is $GPID) to set value of attribute \"AXMinimized\" of window 1 to true" >/dev/null 2>&1
    # Park until peek.sh hands us the next starting directory.
    dir=$(cat "$FIFO")
done
