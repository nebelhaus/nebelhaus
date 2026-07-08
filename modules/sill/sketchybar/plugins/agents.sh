#!/bin/bash
# agents.sh — the reader half of the `agents` bar item (opt-in via
# nebelhaus.sill.plugins). Surfaces the state of your `claude --worktree` agent
# panes in the menu bar so you never have to cycle zellij tabs hunting for the
# one that's blocked on you.
#
# State is written by agents-hook.sh from Claude's own hooks (authoritative — no
# screen-scraping), one file per pane under /tmp/nebelhaus-agents/*.state, each:
#     <state>\t<session>\t<pane-id>\t<label>\t<epoch>
#
# Three entry paths:
#   • agent_update / system_woke / periodic  → recount, repaint icon+label
#   • mouse.clicked                          → (re)build + toggle the popup list
#   • `agents.sh peek <sess> <pane>`         → open a Ghostty live-peek (popup row)
set -u
source "$HOME/.config/sketchybar/colors.sh"

DIR=/tmp/nebelhaus-agents
PLUGINS="$HOME/.config/sketchybar/plugins"
PAW=$(printf '\xEF\x86\xB0')   # nf-fa-paw (U+F1B0) — on-theme for the cat rice

# state → colour + human tag. waiting (a permission prompt) is the urgent one.
state_style() {
  case "$1" in
    waiting) COL=$PEACH; TAG="needs you" ;;
    working) COL=$SKY;   TAG="working"   ;;
    idle)    COL=$GREEN; TAG="done"      ;;
    *)       COL=$TEXT;  TAG="$1"        ;;
  esac
}

# ── popup-row click: live-peek one agent in a throwaway Ghostty ───────────────
if [ "${1:-}" = "peek" ]; then
  open -na Ghostty.app --args --title="peek" \
    --command="/bin/bash $PLUGINS/agents-peek.sh $2 $3"
  sketchybar --set agents popup.drawing=off
  exit 0
fi

# Backstop cleanup: a crashed agent never fires SessionEnd, so reap state files
# untouched for >12h. Live agents re-stamp their epoch on every hook.
[ -d "$DIR" ] && find "$DIR" -name '*.state' -mmin +720 -delete 2>/dev/null

# Iterate the glob with a -e guard rather than an array: macOS bash 3.2 under
# `set -u` throws on "${arr[@]}" when the array is empty, and "no agents" is the
# common case. The literal-pattern-when-no-match is caught by [ -e ].

# ── click: rebuild the popup as one row per agent, then toggle it ─────────────
if [ "${SENDER:-}" = "mouse.clicked" ]; then
  sketchybar --remove '/agents.popup\..*/' 2>/dev/null
  i=0
  for f in "$DIR"/*.state; do
    [ -e "$f" ] || continue
    IFS=$'\t' read -r st sess pane label epoch < "$f"
    state_style "$st"
    sketchybar --add item "agents.popup.$i" popup.agents 2>/dev/null \
      --set "agents.popup.$i" \
        icon="$PAW" icon.color="$COL" icon.font="Hack Nerd Font:Bold:13.0" \
        label="$label · $TAG" label.color="$TEXT" \
        label.font="Hack Nerd Font:Regular:13.0" \
        background.drawing=off \
        click_script="$PLUGINS/agents.sh peek $sess $pane"
    i=$((i + 1))
  done
  if [ "$i" -eq 0 ]; then
    sketchybar --add item agents.popup.0 popup.agents 2>/dev/null \
      --set agents.popup.0 icon.drawing=off label="no active agents" label.color="$SUBTEXT0"
  fi
  sketchybar --set agents popup.drawing=toggle
  exit 0
fi

# ── update: count states, paint the pill by the most-urgent one present ───────
working=0 waiting=0 idle=0
for f in "$DIR"/*.state; do
  [ -e "$f" ] || continue
  IFS=$'\t' read -r st _ < "$f"
  case "$st" in
    working) working=$((working + 1)) ;;
    waiting) waiting=$((waiting + 1)) ;;
    idle)    idle=$((idle + 1)) ;;
  esac
done

if [ $((working + waiting + idle)) -eq 0 ]; then
  sketchybar --set agents drawing=off   # nothing running → no clutter
  exit 0
fi

if   [ "$waiting" -gt 0 ]; then state_style waiting; n=$waiting
elif [ "$working" -gt 0 ]; then state_style working; n=$working
else                           state_style idle;    n=$idle
fi
sketchybar --set agents drawing=on icon="$PAW" icon.color="$COL" \
  label="$n" label.color="$COL"
