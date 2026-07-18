#!/bin/bash
# peek.sh — Super y: summon the floating yazi "peek" panel, rooted at the
# focused pane's cwd.
#
# Why a separate Ghostty instance instead of a zellij floating pane: zellij's
# VTE parser strips kitty-graphics APC sequences, so yazi inside zellij can
# only render chafa block art. Against raw Ghostty, yazi gets the real kitty
# graphics protocol — crisp side-pane previews — and image-preview.sh (the
# Enter opener for images) upgrades itself to full-res kitty rendering too.
#
# Why the window PERSISTS (peek-run.sh keeps it alive after yazi quits):
# every smooth-spawn avenue is a dead end — ghostty's --window-position/
# --window-width CLI configs are silently ignored on macOS (the window
# inherits an AppKit saved-state frame instead), and a macOS-hidden app
# exposes zero AX windows, so a window can't be positioned before it's first
# shown. Any fresh spawn therefore visibly pops somewhere wrong and then
# jumps. So the spawn + center dance runs ONCE (cold path); afterwards the
# window is a panel in all but name: --macos-hidden=always removes it from
# the dock and cmd+tab, q teleports it offscreen (no minimize animation, no
# dock tile), and summoning teleports it back already painted. Aerospace
# floats every runtime ghostty window at detection (see prowl/aerospace.toml)
# so even the cold spawn never tiles or reflows the workspace.

set -u
export PATH="/opt/homebrew/bin:/etc/profiles/per-user/$USER/bin:/run/current-system/sw/bin:$PATH"

FIFO="$HOME/.cache/peek.fifo"
PIDFILE="$HOME/.cache/peek.pid"
RETURNFILE="$HOME/.cache/peek.return"
SESSIONFILE="$HOME/.cache/peek.session"
WINDOW_TITLE="quick-terminal-peek"

# Record where to hand focus back on dismiss (the app the user is in now).
osascript -l JavaScript -e 'ObjC.import("AppKit"); String($.NSWorkspace.sharedWorkspace.frontmostApplication.processIdentifier)' 2>/dev/null > "$RETURNFILE"

# Record which zellij session summoned us, so peek-run.sh (a separate ghostty
# instance, no $ZELLIJ of its own) knows where to open a tab when Enter picks a
# directory. This script runs as a zellij floating pane, so it still has it.
printf '%s\n' "${ZELLIJ_SESSION_NAME:-}" > "$SESSIONFILE"

# The target frame: 85% of the visible frame of the screen the cursor is on,
# centered. Recomputed on every summon (via the shared float-term helper, which
# owns the cursor-screen / visibleFrame centering math) so the panel follows
# the user across displays and survives monitor changes.
read -r POS_X POS_Y WIN_W WIN_H <<< "$("$HOME/.config/zellij/float-term.sh" geom --pct 85)"

# ---- warm path: the peek instance is alive — teleport it in ----------------
if [ -s "$PIDFILE" ]; then
    read -r GPID RPID < "$PIDFILE"
    # GPID may be 0 if the runner failed to identify its instance — and
    # `kill -0 0` would "succeed" (it signals our own process group), so
    # guard the range explicitly.
    if [ "${GPID:-0}" -gt 1 ] 2>/dev/null && kill -0 "$GPID" 2>/dev/null; then
        if ! pgrep -P "$RPID" -x yazi >/dev/null 2>&1; then
            # Runner is parked on the fifo: hand it the cwd, then give yazi a
            # beat to start and paint while the window is still offscreen, so
            # it teleports in already-drawn. The write is backgrounded +
            # reaped so a wedged fifo can never hang the keybind.
            printf '%s\n' "$PWD" > "$FIFO" &
            WRITER=$!
            sleep 0.15
            kill "$WRITER" 2>/dev/null
        fi
        osascript >/dev/null 2>&1 <<APPLESCRIPT
tell application "System Events"
    tell (first process whose unix id is $GPID)
        set position of window 1 to {$POS_X, $POS_Y}
        set size of window 1 to {$WIN_W, $WIN_H}
    end tell
end tell
APPLESCRIPT
        osascript >/dev/null 2>&1 -l JavaScript -e "ObjC.import('AppKit'); \$.NSRunningApplication.runningApplicationWithProcessIdentifier($GPID).activateWithOptions(\$.NSApplicationActivateIgnoringOtherApps);"
        exit 0
    fi
fi

# ---- cold path: spawn the instance and center it (once per boot) ------------

# Reap any stale runner (e.g. its window was closed but the orphan lived on)
# before spawning fresh state.
pkill -f "zellij/peek-run.sh" 2>/dev/null
rm -f "$PIDFILE" "$FIFO"

# `open` hands the instance launchd's minimal PATH; peek-run.sh re-adds the
# nix profile dirs itself. cwd rides in via --working-directory.
open -na Ghostty.app --args \
    --title="$WINDOW_TITLE" \
    --macos-hidden=always \
    --working-directory="$PWD" \
    --command="/bin/bash $HOME/.config/zellij/peek-run.sh"

# peek-run.sh writes the instance pid the moment it starts.
GPID=""
for _ in $(seq 1 150); do
    [ -s "$PIDFILE" ] && { read -r GPID _ < "$PIDFILE"; break; }
    sleep 0.02
done
[ -n "$GPID" ] || exit 0

# Frame the window as soon as AX exposes it. Aerospace already floated it at
# detection, so this is the only geometry event — one quick settle, once.
osascript >/dev/null 2>&1 <<APPLESCRIPT
tell application "System Events"
    tell (first process whose unix id is $GPID)
        repeat 150 times
            try
                if (count windows) > 0 then
                    set position of window 1 to {$POS_X, $POS_Y}
                    set size of window 1 to {$WIN_W, $WIN_H}
                    exit repeat
                end if
            end try
            delay 0.02
        end repeat
    end tell
end tell
APPLESCRIPT
