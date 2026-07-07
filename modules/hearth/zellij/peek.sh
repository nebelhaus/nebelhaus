#!/bin/bash
# peek.sh — Super y: spawn a native, centered, floating Ghostty window running
# yazi, rooted at the focused pane's cwd.
#
# Why a separate Ghostty instance instead of a zellij floating pane: zellij's
# VTE parser strips kitty-graphics APC sequences, so yazi inside zellij can
# only render chafa block art. Against raw Ghostty, yazi gets the real kitty
# graphics protocol — crisp side-pane previews — and image-preview.sh (the
# Enter opener for images) upgrades itself to full-res kitty rendering too.
#
# The spawn/position dance mirrors modules/pounce/commands/rebuild.sh, the
# proven pattern for one-shot "quick-terminal-*" windows:
#   - macOS ghostty can't `-e`/`+new-window` from the CLI; it must be
#     `open -na Ghostty.app --args ...` (a fresh instance).
#   - `--command` overrides ghostty's `command = launch.sh`, so the window
#     runs yazi instead of attaching a nested zellij.
#   - Title `quick-terminal-peek` matches the aerospace float rule, but rule
#     detection can race the title — so we also re-float and re-position the
#     window by PID / window-id after spawn instead of trusting the rule.

set -u

# Runs from a zellij run-pane (nix paths present) but aerospace lives in
# /opt/homebrew/bin, and defensive in case of a bare environment.
export PATH="/opt/homebrew/bin:/etc/profiles/per-user/$USER/bin:/run/current-system/sw/bin:$PATH"

WINDOW_TITLE="quick-terminal-peek"

# Runner for the spawned instance: `open` hands ghostty launchd's minimal
# PATH, so the nix profile dirs must be re-added before exec'ing yazi.
RUN_TMP="/tmp/peek-yazi-run.sh"
cat >"$RUN_TMP" <<'EOF'
#!/bin/bash
export PATH="/etc/profiles/per-user/$USER/bin:/run/current-system/sw/bin:$PATH"
exec yazi
EOF
xattr -d com.apple.quarantine "$RUN_TMP" 2>/dev/null || true

# Find the frame of the screen the user is currently on, in Ghostty's
# top-origin coord system. Pick the screen by cursor location so multi-display
# setups center on the monitor the user is on right now; `visibleFrame`
# excludes menu bar / dock so the window doesn't get clipped.
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
# Rough px→cell factors (rebuild.sh's 80 cols ≈ 750 px, 20 rows ≈ 400 px) so
# the window *spawns* near its final size; AppleScript sets exact pixels.
COLS=$(( WIN_W * 80 / 750 ))
ROWS=$(( WIN_H * 20 / 400 ))

# Capture state BEFORE spawn: the source workspace (to pin the window there
# even if aerospace's catch-all rule grabs it to workspace T) and existing
# ghostty PIDs (to identify the new instance and target it precisely).
SOURCE_WS=$(aerospace list-workspaces --focused 2>/dev/null)
BEFORE_PIDS=$(pgrep -x ghostty 2>/dev/null | sort -u)

open -na Ghostty.app --args \
  --title="$WINDOW_TITLE" \
  --working-directory="$PWD" \
  --window-width=$COLS \
  --window-height=$ROWS \
  --window-position-x=$POS_X \
  --window-position-y=$POS_Y \
  --command="bash $RUN_TMP"

# Step 1: find the PID of the new ghostty instance spawned by `open -na`.
NEW_PID=""
for _ in $(seq 1 100); do
  AFTER_PIDS=$(pgrep -x ghostty 2>/dev/null | sort -u)
  NEW_PID=$(comm -13 <(printf '%s\n' "$BEFORE_PIDS") <(printf '%s\n' "$AFTER_PIDS") | head -1)
  [ -n "$NEW_PID" ] && break
  sleep 0.02
done

# Step 2: exact size + position, targeted at the new instance by PID.
if [ -n "$NEW_PID" ]; then
  osascript >/dev/null 2>&1 <<APPLESCRIPT
tell application "System Events"
  tell (first process whose unix id is $NEW_PID)
    repeat 100 times
      try
        if (count windows) > 0 then
          set size of window 1 to {$WIN_W, $WIN_H}
          set position of window 1 to {$POS_X, $POS_Y}
          exit repeat
        end if
      end try
      delay 0.02
    end repeat
  end tell
end tell
APPLESCRIPT
fi

# Step 3: aerospace cleanup — move the window back to the source workspace
# (in case the catch-all rule already moved it to T) and force-float it.
# Runs after positioning so we don't fight our own AppleScript.
for _ in $(seq 1 30); do
  WID=$(aerospace list-windows --all --format '%{window-id}|%{app-name}|%{window-title}' 2>/dev/null \
        | awk -F'|' -v t="$WINDOW_TITLE" '$2 == "Ghostty" && $3 == t {print $1; exit}')
  if [ -n "$WID" ]; then
    [ -n "$SOURCE_WS" ] && aerospace move-node-to-workspace --window-id "$WID" "$SOURCE_WS" 2>/dev/null
    aerospace layout --window-id "$WID" floating 2>/dev/null
    break
  fi
  sleep 0.03
done

# Floating may have restored a stale pre-float frame — reassert the geometry.
if [ -n "$NEW_PID" ]; then
  osascript >/dev/null 2>&1 <<APPLESCRIPT
tell application "System Events"
  tell (first process whose unix id is $NEW_PID)
    try
      set size of window 1 to {$WIN_W, $WIN_H}
      set position of window 1 to {$POS_X, $POS_Y}
    end try
  end tell
end tell
APPLESCRIPT
fi
