#!/usr/bin/env bash
# statusline.sh — nebelhaus agent-worktree statusline for Claude Code.
#
# Row 1  : THIS session's worktree name + ONE status token (see render_status).
# Row 2+ : sister agent worktrees with in-flight work across ALL repos, each with
#          its "org/repo", name, and the same one status token (+ PR number).
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
MAX_ROWS=6      # cap sister rows; extras collapse into a "+N more" line

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

in=$(cat)
cwd=$(printf '%s' "$in" | jq -r '.workspace.current_dir // .cwd // empty')
wt_name=$(printf '%s' "$in" | jq -r '.worktree.name // .workspace.git_worktree // empty')
ctx=$(printf '%s' "$in" | jq -r '.context_window.used_percentage // empty')
cost=$(printf '%s' "$in" | jq -r '.cost.total_cost_usd // empty')
[ -z "$cwd" ] && cwd="$PWD"

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
# purge (worktree only): clean tree AND branch merged into main => `wt` reaps it.
purge=0
if [ "$is_wt" = 1 ] && [ "${files:-0}" -eq 0 ] && g merge-base --is-ancestor HEAD "$def" 2>/dev/null; then
  purge=1
fi

# --- ROW 1 : name + one status token (no repo name, no "clean") ----------------
st=$(render_status "$ahead" "$files" "$ins" "$del" "" "$purge" 0)
if [ "$is_wt" = 1 ]; then
  row1="${DOT}●${R} ${NAME}${wt_name}${R}"
elif [ -n "$branch" ]; then
  row1="${DOT}●${R} ${NAME}${branch}${R}"
else
  row1="${DIM}$(basename "$cwd")${R}"
fi
[ -n "$st" ] && row1="$row1  $st"
tail=""
[ -n "$ctx" ]  && tail="${DIM}${ctx}%ctx${R}"
[ -n "$cost" ] && [ "$cost" != "0" ] && tail="${tail:+$tail }${DIM}\$$(printf '%.2f' "$cost" 2>/dev/null)${R}"
[ -n "$tail" ] && row1="$row1   $tail"
printf '%b\n' "$row1"

# --- ROW 2+ : sister worktree panel (cache; refresh detached if stale) ---------
stale=1
if [ -f "$PANEL" ]; then
  age=$(( $(date +%s) - $(stat -f %m "$PANEL" 2>/dev/null || echo 0) ))
  [ "$age" -lt "$TTL" ] && stale=0
fi
[ "$stale" = 1 ] && [ -x "$REFRESHER" ] && { nohup "$REFRESHER" >/dev/null 2>&1 & disown 2>/dev/null || true; }

[ -f "$PANEL" ] || exit 0
cur_slug=$(g remote get-url origin 2>/dev/null | sed -E 's@\.git$@@; s@^.*[:/]([^/]+/[^/]+)$@\1@')
shown=0; extra=0
while IFS=$'\t' read -r pslug pname pahead pfiles pins pdel ppr; do
  [ -n "$pname" ] || continue
  [ "$pslug" = "$cur_slug" ] && [ "$pname" = "$wt_name" ] && continue   # skip self
  if [ "$shown" -ge "$MAX_ROWS" ]; then extra=$((extra+1)); continue; fi
  pst=$(render_status "$pahead" "$pfiles" "$pins" "$pdel" "$ppr" 0 1)
  owner="${pslug%%/*}"; rname="${pslug##*/}"
  disp="$pname"; [ ${#disp} -gt 22 ] && disp="${disp:0:21}…"
  printf '%b\n' "  ${GRAY}○${R} ${DIM}${owner}/${R}${rname} ${disp}${pst:+  $pst}"
  shown=$((shown+1))
done <"$PANEL"
[ "$extra" -gt 0 ] && printf '%b\n' "  ${DIM}+${extra} more${R}"
exit 0
