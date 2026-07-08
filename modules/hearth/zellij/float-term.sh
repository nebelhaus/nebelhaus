#!/bin/bash
# float-term.sh — the ONE way the nebelhaus rice throws up a floating, centered
# Ghostty window. Consolidates logic that used to be copy-pasted (and to drift)
# across the Rebuild System pounce command, the Super-y yazi peek panel, and
# the agent-peek popup.
#
# Two subcommands:
#
#   geom [--pct N | --w PX --h PX]
#       Print "X Y W H": a window of the requested size, centered on the
#       VISIBLE frame (menubar/dock excluded) of whichever display the cursor
#       is on right now. Multi-monitor aware; coords are Ghostty/AppKit
#       top-left origin. --pct sizes the window to N% of the visible frame.
#       Callers that manage their own window (peek's warm-path teleport and its
#       --macos-hidden cold spawn) consume this for the centering MATH only.
#
#   spawn --title T [--pct N | --w PX --h PX] [--cols N --rows N] [--pin]
#         --command CMD [-- EXTRA ghostty args…]
#       Spawn a fresh Ghostty INSTANCE running CMD, centered at that geometry,
#       and print its pid. macOS forces this exact shape:
#         - `ghostty -e …` / `+new-window` are unsupported from the CLI, so we
#           must `open -na Ghostty.app` to get a fresh instance;
#         - that instance's --window-position/-width flags are silently ignored
#           on macOS (it inherits a saved-state frame), so we PID-diff to find
#           the new instance and drive System Events to set the real frame once
#           AX first exposes the window.
#       Aerospace's "every runtime ghostty floats" rule (prowl/aerospace.toml)
#       keeps it from tiling; --pin also yanks it back onto the workspace you
#       spawned from and force-floats it, in case any on-window-detected rule
#       grabbed it first.

set -u
# open/osascript live in /usr/bin; aerospace in the nix/brew profiles. Callers
# range from a login shell to launchd's minimal PATH (pounce command), so be
# explicit rather than trust the inherited environment.
export PATH="/opt/homebrew/bin:/run/current-system/sw/bin:/usr/bin:/bin:$PATH"

# ── centered geometry on the cursor's screen ────────────────────────────────
# Emits "X Y W H" for a WIN_W×WIN_H window centered on the visible frame of the
# display under the cursor. Pass either an explicit pixel size or a percentage.
geom() {
  local mode="pct" arg="85"
  while [ $# -gt 0 ]; do
    case "$1" in
      --pct) mode="pct"; arg="$2"; shift 2 ;;
      --w)   mode="px";  W_PX="$2"; shift 2 ;;
      --h)             H_PX="$2"; shift 2 ;;
      *) shift ;;
    esac
  done

  # Frame of the cursor's screen in Ghostty's top-origin coord system. `frame`
  # would include the menu bar / dock; `visibleFrame` excludes them so a
  # centered window never gets clipped.
  local frame
  frame=$(osascript -l JavaScript -e '
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
  [ -z "$frame" ] && frame="0 0 1920 1080"

  local sx sy sw sh win_w win_h
  read -r sx sy sw sh <<< "$frame"
  if [ "$mode" = "pct" ]; then
    win_w=$(( sw * arg / 100 ))
    win_h=$(( sh * arg / 100 ))
  else
    win_w="${W_PX:?--w required}"
    win_h="${H_PX:?--h required}"
  fi
  echo "$(( sx + (sw - win_w) / 2 )) $(( sy + (sh - win_h) / 2 )) $win_w $win_h"
}

# ── spawn a fresh centered instance ─────────────────────────────────────────
spawn() {
  local title="" command="" pin=0 cols="" rows=""
  local -a size_args=() extra=()
  while [ $# -gt 0 ]; do
    case "$1" in
      --title)   title="$2"; shift 2 ;;
      --command) command="$2"; shift 2 ;;
      --pin)     pin=1; shift ;;
      --cols)    cols="$2"; shift 2 ;;
      --rows)    rows="$2"; shift 2 ;;
      --pct)     size_args=(--pct "$2"); shift 2 ;;
      --w)       size_args+=(--w "$2"); shift 2 ;;
      --h)       size_args+=(--h "$2"); shift 2 ;;
      --)        shift; extra=("$@"); break ;;
      *) shift ;;
    esac
  done
  : "${title:?--title required}" "${command:?--command required}"

  # ${arr[@]+"${arr[@]}"}: expand safely even when empty — macOS /bin/bash is
  # 3.2, where a bare "${arr[@]}" on an empty array trips `set -u`.
  local pos_x pos_y win_w win_h
  read -r pos_x pos_y win_w win_h <<< "$(geom ${size_args[@]+"${size_args[@]}"})"

  # Snapshot before spawn: existing ghostty pids so we can pick out the NEW
  # instance, and the focused workspace so --pin can put the window there.
  local before source_ws=""
  before=$(pgrep -x ghostty 2>/dev/null | sort -u)
  [ "$pin" = 1 ] && source_ws=$(aerospace list-workspaces --focused 2>/dev/null)

  local -a open_args=(--title="$title")
  [ -n "$cols" ] && open_args+=(--window-width="$cols")
  [ -n "$rows" ] && open_args+=(--window-height="$rows")
  open_args+=(--window-position-x="$pos_x" --window-position-y="$pos_y")
  open_args+=(${extra[@]+"${extra[@]}"} --command="$command")
  open -na Ghostty.app --args "${open_args[@]}"

  # Find the new instance (poll fast — detection dominates perceived latency).
  local new_pid="" after
  local i
  for i in $(seq 1 100); do
    after=$(pgrep -x ghostty 2>/dev/null | sort -u)
    new_pid=$(comm -13 <(printf '%s\n' "$before") <(printf '%s\n' "$after") | head -1)
    [ -n "$new_pid" ] && break
    sleep 0.02
  done

  # Set the real frame the moment AX exposes the window (CLI flags don't stick).
  if [ -n "$new_pid" ]; then
    osascript >/dev/null 2>&1 <<APPLESCRIPT
tell application "System Events"
  tell (first process whose unix id is $new_pid)
    repeat 100 times
      try
        if (count windows) > 0 then
          set size of window 1 to {$win_w, $win_h}
          set position of window 1 to {$pos_x, $pos_y}
          exit repeat
        end if
      end try
      delay 0.02
    end repeat
  end tell
end tell
APPLESCRIPT
  fi

  # Aerospace cleanup: pull the window back to the source workspace (if asked)
  # and force-float it. Runs after positioning so we don't fight our own AS.
  for i in $(seq 1 30); do
    local wid
    wid=$(aerospace list-windows --all --format '%{window-id}|%{app-name}|%{window-title}' 2>/dev/null \
          | awk -F'|' -v t="$title" '$2 == "Ghostty" && $3 == t {print $1; exit}')
    if [ -n "$wid" ]; then
      [ -n "$source_ws" ] && aerospace move-node-to-workspace --window-id "$wid" "$source_ws" 2>/dev/null
      aerospace layout --window-id "$wid" floating 2>/dev/null
      break
    fi
    sleep 0.03
  done

  echo "$new_pid"
}

case "${1:-}" in
  geom)  shift; geom "$@" ;;
  spawn) shift; spawn "$@" ;;
  *) echo "usage: float-term.sh {geom|spawn} …" >&2; exit 2 ;;
esac
