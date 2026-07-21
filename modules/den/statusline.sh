#!/usr/bin/env bash
# statusline.sh — nebelhaus agent-worktree statusline for Claude Code.
#
# Row 1  : THIS session's worktree name + ONE status token (see render_status).
# Row 2+ : the worktrees THIS session spawned (its direct children via ⌘C /
#          `claude --worktree`), across whatever repos they live in — each with
#          its repo, name, the same status token, and GitHub PR state.
#
# Lineage: `wt create` records each worktree's parent (the cwd it was spawned
# from) in its registry; the refresher carries that into panel.tsv, and a
# session lists only the rows whose parent == its own cwd.
#
# The status token is a single mutually-exclusive slot:
#     ⏏  (orange)   branch is merged/landed → `wt` reaps it on pane close
#     N^ (blue)     N commits on the branch, not yet merged
#     +A -D         uncommitted line changes (green/red), when no commits yet
#     (empty)       nothing differs from main → show nothing (no "clean")
#
# Cheap local git runs inline every render; the cross-repo + gh enumeration is
# done DETACHED by statusline-refresh.sh and cached (stale-while-revalidate).
# Pair with: "statusLine":{"command":"…/statusline.sh","refreshInterval":12}
PATH="/run/current-system/sw/bin:/nix/var/nix/profiles/default/bin:/etc/profiles/per-user/$(id -un 2>/dev/null)/bin:/opt/homebrew/bin:/usr/bin:/bin:${PATH:-}"

CACHE_DIR="${CLAUDE_STATUSLINE_CACHE:-$HOME/.cache/claude-statusline}"
PANEL="$CACHE_DIR/panel.tsv"
# Refresher: the rice ships it on PATH as `claude-statusline-refresh`; fall back
# to the sibling script when running straight out of ~/.claude (pre-rebuild).
REFRESHER="$(command -v claude-statusline-refresh 2>/dev/null || echo "$HOME/.claude/statusline-refresh.sh")"
TTL=15          # seconds before the sister-repo panel is considered stale
MAX_ROWS=8      # cap child rows; extras collapse into a "+N more" line

# 256-colour palette — muted, rice-consistent (cf. `wt`: 103 gray, 167 red).
c() { printf '\033[38;5;%sm' "$1"; }
DOT=$(c 108); DIM=$(c 244); GRAY=$(c 103); NAME=$'\033[1m'
AHEAD=$(c 75); ADD=$(c 71); DEL=$(c 167); PURGE=$(c 173)
PR_OPEN=$(c 71); PR_MERGED=$(c 139); PR_CLOSED=$(c 167)
R=$'\033[0m'

# render_status <ahead> <files> <ins> <del> <prstate> <purge> <want_pr>
# Emits the single status token. purge=1 => branch would be reaped (row-1 only).
render_status() {
  local ahead=${1:-0} files=${2:-0} ins=${3:-0} del=${4:-0} pr="$5" purge=${6:-0} want_pr=${7:-0}
  local st="" state="${pr##* }" num="${pr%% *}"
  local done=0; { [ "$purge" = 1 ] || [ "$state" = merged ]; } && done=1
  if [ "$done" = 1 ]; then
    st="${PURGE}⏏${R}"
  elif [ "$ahead" -gt 0 ] 2>/dev/null; then
    st="${AHEAD}${ahead}^${R}"
  elif [ "$files" -gt 0 ] 2>/dev/null; then
    [ "${ins:-0}" -gt 0 ] && st="${ADD}+${ins}${R}"
    [ "${del:-0}" -gt 0 ] && st="${st:+$st }${DEL}-${del}${R}"
  fi
  if [ "$want_pr" = 1 ] && [ -n "$pr" ]; then
    local col="$DIM"
    case "$state" in open) col="$PR_OPEN";; merged) col="$PR_MERGED";; closed) col="$PR_CLOSED";; esac
    st="${st:+$st }${col}${num}${R}"
  fi
  printf '%s' "$st"
}
plain() { printf '%s' "$1" | sed 's/\x1b\[[0-9;]*m//g'; }   # strip ANSI for width

in=$(cat)
j() { printf '%s' "$in" | jq -r "$1 // empty"; }
cwd=$(j '.workspace.current_dir // .cwd'); [ -z "$cwd" ] && cwd="$PWD"
wt_name=$(j '.worktree.name // .workspace.git_worktree')
ctx=$(j '.context_window.used_percentage')
cost=$(j '.cost.total_cost_usd')
COLS=${COLUMNS:-120}

# Model tier indicator, zero-width: the row-1 bullet turns into a purple ✦ when
# the session runs a Mythos-class model (fable/mythos in model.id).
BULLET="${DOT}●${R}"
case "$(j '.model.id')" in
  *fable*|*mythos*) BULLET="$(c 176)✦${R}";;
esac

g() { git -C "$cwd" --no-optional-locks "$@" 2>/dev/null; }
branch=$(g branch --show-current)
is_wt=0
[ -n "$wt_name" ] && is_wt=1
[ "$is_wt" = 0 ] && case "$branch" in worktree-*) is_wt=1; wt_name="${branch#worktree-}";; esac

def=$(g symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null | sed 's@^origin/@@')
[ -z "$def" ] && { for b in main master; do g show-ref -q --verify "refs/heads/$b" && def=$b && break; done; }
[ -z "$def" ] && def=main

files=$(g status --porcelain | grep -c .)
ahead=$(g rev-list --count "$def..HEAD" 2>/dev/null || echo 0)
ins=0; del=0
if [ "${files:-0}" -gt 0 ]; then
  read -r ins del < <(g diff HEAD --shortstat | awk '{i=0;d=0;for(k=1;k<=NF;k++){if($k~/insertion/)i=$(k-1);if($k~/deletion/)d=$(k-1)}print i" "d}')
  ins=${ins:-0}; del=${del:-0}
fi
purge=0
if [ "$is_wt" = 1 ] && [ "${files:-0}" -eq 0 ] && g merge-base --is-ancestor HEAD "$def" 2>/dev/null; then
  purge=1
fi

# Row 1's ⏏ ("landed → wt reaps on close") normally comes from local ancestry
# (purge). But a squash/rebase merge lands the work under a NEW commit, so the
# branch is never an ancestor of main even though its PR merged. The detached
# refresher already cached this branch's PR state in the panel; read our own row
# (gh-free in the render path) so a merged PR lights the ⏏ too. want_pr stays 0,
# so row 1 gets the icon without the PR number.
own_pr=""
if [ "$is_wt" = 1 ] && [ "$purge" = 0 ] && [ -f "$PANEL" ]; then
  # Match our own panel row by (slug, name). slug is the remote-derived owner/name
  # (same parse the refresher uses) — NOT the local dir name, which can differ
  # (e.g. dir "nebelhaus" but slug "nebelhaus/workshop").
  slug=$(g remote get-url origin 2>/dev/null)
  slug=${slug%.git}; slug=${slug#*://}; slug=${slug#*@}; slug=${slug#*[:/]}
  if [ -n "$slug" ]; then
    own_pr=$(awk -F'\t' -v n="$wt_name" -v s="$slug" \
      '$1==s && $2==n { print $7; exit }' "$PANEL")
    [ "$own_pr" = "-" ] && own_pr=""
  fi
fi

# --- ROW 1 : name + one status token (no repo name, no "clean") ----------------
st=$(render_status "$ahead" "$files" "$ins" "$del" "$own_pr" "$purge" 0)
if [ "$is_wt" = 1 ]; then
  row1="${BULLET} ${NAME}${wt_name}${R}"
elif [ -n "$branch" ]; then
  row1="${BULLET} ${NAME}${branch}${R}"
else
  row1="${BULLET} ${DIM}$(basename "$cwd")${R}"
fi
[ -n "$st" ] && row1="$row1  $st"
tailseg=""
[ -n "$ctx" ]  && tailseg="${DIM}${ctx}%${R}"
[ -n "$cost" ] && [ "$cost" != "0" ] && tailseg="${tailseg:+$tailseg }${DIM}\$$(printf '%.2f' "$cost" 2>/dev/null)${R}"
[ -n "$tailseg" ] && row1="$row1   $tailseg"
printf '%b\n' "$row1"

# --- refresh the (shared) panel cache if stale, detached --------------------
stale=1
if [ -f "$PANEL" ]; then
  age=$(( $(date +%s) - $(stat -f %m "$PANEL" 2>/dev/null || echo 0) ))
  [ "$age" -lt "$TTL" ] && stale=0
fi
[ "$stale" = 1 ] && [ -x "$REFRESHER" ] && { nohup "$REFRESHER" >/dev/null 2>&1 & disown 2>/dev/null || true; }

# --- ROW 2+ : only the worktrees THIS session spawned (panel parent == cwd) ----
[ -f "$PANEL" ] || exit 0
shown=0; extra=0
while IFS=$'\t' read -r pslug pname pahead pfiles pins pdel ppr pparent; do
  [ -n "$pname" ] || continue
  [ "$ppr" = "-" ] && ppr=""                    # decode empty-prstate sentinel
  [ "$pparent" = "$cwd" ] || continue           # only worktrees I spawned
  if [ "$shown" -ge "$MAX_ROWS" ]; then extra=$((extra+1)); continue; fi
  pst=$(render_status "$pahead" "$pfiles" "$pins" "$pdel" "$ppr" 0 1)
  repo="${pslug##*/}"
  # width-aware truncation: only clip the name if the row would exceed COLS
  stplain=$(plain "$pst"); stlen=${#stplain}
  budget=$(( COLS - 4 - ${#repo} - 1 - stlen - 4 ))
  [ "$budget" -lt 8 ] && budget=8
  disp="$pname"
  [ ${#disp} -gt "$budget" ] && disp="${disp:0:budget-1}…"
  printf '%b\n' "  ${GRAY}○${R} ${DIM}${repo}${R} ${disp}${pst:+  $pst}"
  shown=$((shown+1))
done <"$PANEL"
[ "$extra" -gt 0 ] && printf '%b\n' "  ${DIM}+${extra} more${R}"
exit 0
