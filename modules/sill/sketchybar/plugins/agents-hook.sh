#!/bin/bash
# agents-hook.sh — the writer half of the `agents` bar item. Claude Code runs
# this from its own hooks, and because those hooks are children of a `claude`
# process living INSIDE a zellij pane, they inherit $ZELLIJ_SESSION_NAME +
# $ZELLIJ_PANE_ID — so each agent self-reports its exact state AND its subscribe
# target. No pane-id discovery, no screen-scraping. (Wired in the host's
# settings.json: UserPromptSubmit→working, Notification→waiting, Stop→idle,
# SessionEnd→remove. See modules/sill/default.nix for the reader, agents.sh.)
#
#   usage: agents-hook.sh <working|waiting|idle|remove>
set -u
DIR=/tmp/nebelhaus-agents

# Only track claude panes that live in zellij — a bare-terminal claude has no
# pane to peek and no place on the bar, so stay invisible there.
[ -n "${ZELLIJ_PANE_ID:-}" ] || exit 0

st="${1:-working}"
sess="${ZELLIJ_SESSION_NAME:-nosession}"
pane="terminal_${ZELLIJ_PANE_ID}"
f="$DIR/${sess}__${pane}.state"
mkdir -p "$DIR"

if [ "$st" = remove ]; then
  rm -f "$f"
else
  # Label the agent by its checkout (worktree/repo basename) — far more useful in
  # the popup than the shared "main" session name every agent pane reports.
  label=$(basename "${CLAUDE_PROJECT_DIR:-$PWD}")
  printf '%s\t%s\t%s\t%s\t%s\n' "$st" "$sess" "$pane" "$label" "$(date +%s)" > "$f"
fi

# Repaint the bar now by running the reader directly — the only reliable path.
# A hidden item's own update_freq never ticks (so it could never re-show itself),
# and sketchybar delivers custom --trigger events inconsistently across reloads;
# a plain invocation of agents.sh (which fixes up its own PATH) always works.
SENDER=refresh NAME=agents "$(dirname "$0")/agents.sh" >/dev/null 2>&1 || true
exit 0
