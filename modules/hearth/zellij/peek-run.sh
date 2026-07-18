#!/bin/bash
# peek-run.sh — runs INSIDE the peek ghostty instance (spawned by peek.sh).
#
# Keeps the peek window alive across yazi sessions, panel-style: when yazi
# quits (q/Esc), the window teleports offscreen (bottom-right, the same
# parking trick aerospace uses — no minimize animation, no dock tile; the
# instance runs --macos-hidden=always so it has no dock icon or cmd+tab
# entry either) and focus is handed back to wherever the user summoned from.
# This script then parks on a fifo waiting for the next summon. peek.sh
# writes a directory to the fifo, lets yazi repaint while offscreen, and
# teleports the window back — instant and seamless in both directions.

set -u
export PATH="/etc/profiles/per-user/$USER/bin:/run/current-system/sw/bin:$PATH"

# macOS `open` forwards the caller's environment, so the zellij pane that ran
# peek.sh leaks $ZELLIJ & co. into this instance — making yazi and
# image-preview.sh believe they're inside zellij and downgrade crisp kitty
# graphics to block art. This window is raw ghostty; scrub the lie.
unset ZELLIJ ZELLIJ_SESSION_NAME ZELLIJ_PANE_ID

# PEEK=1 tells the peek-open yazi plugin (Enter) it's running inside peek, so a
# directory picks → new tab instead of yazi's default open. Unset everywhere
# else, so a plain `yy` session keeps the default Enter.
export PEEK=1

FIFO="$HOME/.cache/peek.fifo"
PIDFILE="$HOME/.cache/peek.pid"
RETURNFILE="$HOME/.cache/peek.return"
SESSIONFILE="$HOME/.cache/peek.session"
CWDFILE="$HOME/.cache/peek.cwd"

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

dismiss() {
    # Teleport offscreen — ask for the far corner and let macOS clamp to
    # whatever it allows (a sliver below the screen edge).
    osascript >/dev/null 2>&1 -e "tell application \"System Events\" to tell (first process whose unix id is $GPID) to set position of window 1 to {9999, 9999}"
    # Hand focus back to the app the user summoned from (peek.sh records it);
    # without this, keystrokes would keep landing in the invisible window.
    local rpid
    rpid=$(cat "$RETURNFILE" 2>/dev/null)
    kill -0 "${rpid:-0}" 2>/dev/null || rpid=$(pgrep -x ghostty | sort -n | head -1)
    [ -n "${rpid:-}" ] && osascript >/dev/null 2>&1 -l JavaScript -e "ObjC.import('AppKit'); \$.NSRunningApplication.runningApplicationWithProcessIdentifier($rpid).activateWithOptions(\$.NSApplicationActivateIgnoringOtherApps);"
}

# spawn_tab DIR — open a new zellij tab cwd'd at DIR in the session that
# summoned peek (peek.sh recorded it). We're a bare ghostty instance with no
# $ZELLIJ, so target the server explicitly with `zellij -s <session> action`.
# Name the tab after its git root (or dir basename), same as the link-handler.
# `new-tab --cwd` is silently ignored under a custom default_tab_template, so
# clone the active layout and inject a tab-level cwd (the only form zellij
# honors) — the same trick the link-handler uses.
spawn_tab() {
    local dir="$1" session name root layout_src esc gen
    session=$(cat "$SESSIONFILE" 2>/dev/null)
    [ -n "$session" ] || return 0

    name="$(basename "$dir")"
    root="$(git -C "$dir" rev-parse --show-toplevel 2>/dev/null)"
    [ -n "$root" ] && name="$(basename "$root")"

    layout_src="$HOME/.config/zellij/layouts/custom.kdl"
    gen=""
    if [ -f "$layout_src" ]; then
        # KDL-escape the path (backslash then double-quote) for the cwd string.
        esc="${dir//\\/\\\\}"; esc="${esc//\"/\\\"}"
        # Reused/overwritten each pick — no per-invocation temp to race cleanup.
        gen="${TMPDIR:-/tmp}/zellij-peek-tab-$USER.kdl"
        awk -v cwd="$esc" '
            /^    tab \{$/ && !done { print "    tab cwd=\"" cwd "\" {"; done=1; next }
            { print }
        ' "$layout_src" > "$gen"
        grep -q '^    tab cwd=' "$gen" || gen=""
    fi

    if [ -n "$gen" ]; then
        zellij -s "$session" action new-tab --layout "$gen" --name "$name" 2>/dev/null
    else
        # Fallback (layout missing/reshaped): name the tab; cwd may land in $HOME.
        zellij -s "$session" action new-tab --cwd "$dir" --name "$name" 2>/dev/null
    fi
}

dir="$PWD"
while :; do
    [ -d "$dir" ] || dir="$HOME"
    # Clear any prior pick so only THIS session's Enter-on-dir counts.
    rm -f "$CWDFILE"
    yazi "$dir"
    # Enter on a directory (peek-open.yazi) drops its path here and quits yazi.
    picked=$(cat "$CWDFILE" 2>/dev/null); rm -f "$CWDFILE"
    [ -n "$picked" ] && [ -d "$picked" ] && spawn_tab "$picked"
    dismiss
    # Park until peek.sh hands us the next starting directory.
    dir=$(cat "$FIFO")
done
