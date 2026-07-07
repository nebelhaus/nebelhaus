#!/bin/bash
# peek.sh — Super y: summon the floating yazi "peek" window, rooted at the
# focused pane's cwd.
#
# Why a separate Ghostty instance instead of a zellij floating pane: zellij's
# VTE parser strips kitty-graphics APC sequences, so yazi inside zellij can
# only render chafa block art. Against raw Ghostty, yazi gets the real kitty
# graphics protocol — crisp side-pane previews — and image-preview.sh (the
# Enter opener for images) upgrades itself to full-res kitty rendering too.
#
# Why the window PERSISTS (peek-run.sh keeps it alive, hidden, after yazi
# quits): every smooth-spawn avenue is a dead end — ghostty's
# --window-position/--window-width CLI configs are silently ignored on macOS
# (the window inherits an AppKit saved-state frame instead), and a macOS
# -hidden app exposes zero AX windows, so a window can't be positioned before
# it's first shown. Any fresh spawn therefore visibly pops somewhere wrong
# and then jumps. So we pay the spawn + center dance ONCE (cold path); after
# that, q merely hides the window and summoning is an instant unhide of an
# already-perfect frame. Aerospace floats every runtime ghostty window at
# detection (see prowl/aerospace.toml), so even the cold spawn never tiles or
# reflows the workspace.

set -u
export PATH="/opt/homebrew/bin:/etc/profiles/per-user/$USER/bin:/run/current-system/sw/bin:$PATH"

FIFO="$HOME/.cache/peek.fifo"
PIDFILE="$HOME/.cache/peek.pid"
WINDOW_TITLE="quick-terminal-peek"

# ---- warm path: the peek instance is alive — just summon it -----------------
if [ -s "$PIDFILE" ]; then
    read -r GPID RPID < "$PIDFILE"
    # GPID may be 0 if the runner failed to identify its instance — and
    # `kill -0 0` would "succeed" (it signals our own process group), so
    # guard the range explicitly.
    if [ "${GPID:-0}" -gt 1 ] 2>/dev/null && kill -0 "$GPID" 2>/dev/null; then
        if ! pgrep -P "$RPID" -x yazi >/dev/null 2>&1; then
            # Runner is parked on the fifo: hand it the cwd, then give yazi a
            # beat to start and paint before the reveal, so the window appears
            # already-drawn. The write is backgrounded + reaped so a wedged
            # fifo can never hang the keybind.
            printf '%s\n' "$PWD" > "$FIFO" &
            WRITER=$!
            sleep 0.15
            kill "$WRITER" 2>/dev/null
        fi
        # Restore (un-minimize) and focus. By now yazi has repainted, so the
        # restore animation reveals an already-drawn browser.
        osascript >/dev/null 2>&1 -e "tell application \"System Events\" to tell (first process whose unix id is $GPID) to set value of attribute \"AXMinimized\" of window 1 to false"
        osascript >/dev/null 2>&1 -l JavaScript -e "ObjC.import('AppKit'); \$.NSRunningApplication.runningApplicationWithProcessIdentifier($GPID).activateWithOptions(\$.NSApplicationActivateIgnoringOtherApps);"
        exit 0
    fi
fi

# ---- cold path: spawn the instance and center it (once per boot) ------------

# Find the visible frame of the screen the cursor is on, in top-origin coords.
FRAME=$(osascript -l JavaScript -e '
  ObjC.import("AppKit");
  ObjC.import("CoreGraphics");
  var loc = $.CGEventGetLocation($.CGEventCreate($()));
  var screens = $.NSScreen.screens;
  if (screens.count === 0) {
    "0 0 1920 1080";
  } else {
    var primaryH = screens.objectAtIndex(0).frame.size.height;
    var pick = screens.objectAtIndex(0);
    for (var i = 0; i < screens.count; i++) {
      var s = screens.objectAtIndex(i);
      var fr = s.frame;
      var topY = primaryH - (fr.origin.y + fr.size.height);
      if (loc.x >= fr.origin.x && loc.x < fr.origin.x + fr.size.width &&
          loc.y >= topY      && loc.y < topY      + fr.size.height) {
        pick = s; break;
      }
    }
    var vf = pick.visibleFrame;
    var vTopY = primaryH - (vf.origin.y + vf.size.height);
    Math.round(vf.origin.x) + " " + Math.round(vTopY) + " " +
    Math.round(vf.size.width) + " " + Math.round(vf.size.height);
  }
' 2>/dev/null)
[ -z "$FRAME" ] && FRAME="0 0 1920 1080"
read -r SCREEN_X SCREEN_Y SCREEN_W SCREEN_H <<< "$FRAME"

# 85% of the visible frame, centered.
WIN_W=$(( SCREEN_W * 85 / 100 ))
WIN_H=$(( SCREEN_H * 85 / 100 ))
POS_X=$(( SCREEN_X + (SCREEN_W - WIN_W) / 2 ))
POS_Y=$(( SCREEN_Y + (SCREEN_H - WIN_H) / 2 ))

# Reap any stale runner (e.g. its window was closed but the orphan lived on)
# before spawning fresh state.
pkill -f "zellij/peek-run.sh" 2>/dev/null
rm -f "$PIDFILE" "$FIFO"

# `open` hands the instance launchd's minimal PATH; peek-run.sh re-adds the
# nix profile dirs itself. cwd rides in via --working-directory.
open -na Ghostty.app --args \
    --title="$WINDOW_TITLE" \
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
