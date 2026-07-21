#!/usr/bin/env bash
# statusline.sh — nebelhaus agent-worktree statusline for Claude Code.
#
# Row 1  : THIS session's worktree name + ONE status token (see render_status),
#          then flush right: ctx% · cost · permission-mode icon (⏸ plan, ⏵⏵
#          auto/accept/bypass, ⊘ dontAsk — read from the transcript tail).
# Row 2+ : the worktrees THIS session spawned (its direct children via ⌘C /
#          `claude --worktree`), across whatever repos they live in — each as
#          repo, PR number (left of the name, colored by PR state), name, and
#          the same status token as row 1.
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

# render_status <ahead> <files> <ins> <del> <prstate> <purge>
# Emits the single status token. purge=1 => branch would be reaped (row-1 only).
# prstate only feeds the merged→⏏ check; the PR number itself is rendered by
# render_pr as its own segment, left of the worktree name.
render_status() {
  local ahead=${1:-0} files=${2:-0} ins=${3:-0} del=${4:-0} pr="$5" purge=${6:-0}
  local st="" state="${pr##* }"
  local done=0; { [ "$purge" = 1 ] || [ "$state" = merged ]; } && done=1
  if [ "$done" = 1 ]; then
    st="${PURGE}⏏${R}"
  elif [ "$ahead" -gt 0 ] 2>/dev/null; then
    st="${AHEAD}${ahead}^${R}"
  elif [ "$files" -gt 0 ] 2>/dev/null; then
    [ "${ins:-0}" -gt 0 ] && st="${ADD}+${ins}${R}"
    [ "${del:-0}" -gt 0 ] && st="${st:+$st }${DEL}-${del}${R}"
  fi
  printf '%s' "$st"
}

# render_pr <prstate> — "#N" colored by PR state, or nothing when there's no PR.
render_pr() {
  local pr="$1" state="${1##* }" col="$DIM"
  [ -n "$pr" ] || return 0
  case "$state" in open) col="$PR_OPEN";; merged) col="$PR_MERGED";; closed) col="$PR_CLOSED";; esac
  printf '%s' "${col}${pr%% *}${R}"
}
plain() { printf '%s' "$1" | sed 's/\x1b\[[0-9;]*m//g'; }   # strip ANSI for width

in=$(cat)
j() { printf '%s' "$in" | jq -r "$1 // empty"; }
cwd=$(j '.workspace.current_dir // .cwd'); [ -z "$cwd" ] && cwd="$PWD"
wt_name=$(j '.worktree.name // .workspace.git_worktree')
ctx=$(j '.context_window.used_percentage')
cost=$(j '.cost.total_cost_usd')
transcript=$(j '.transcript_path')
COLS=${COLUMNS:-120}

# Permission mode: NOT in the statusline stdin, but Claude Code appends a
# {"type":"permission-mode","permissionMode":"…"} record to the transcript on
# every mode change (and stamps user records too), and re-runs the statusline
# when the mode flips — so the last occurrence in the transcript tail IS the
# live mode, no hook or stash file needed. 64KB of tail keeps this O(1).
mode=""
[ -n "$transcript" ] && [ -f "$transcript" ] &&
  mode=$(tail -c 65536 "$transcript" 2>/dev/null |
    grep -o '"permissionMode": *"[a-zA-Z]*"' | tail -1 | grep -o '[a-zA-Z]*"$')
mode=${mode%\"}

# Model tier indicator: a ✦ ONLY when the session runs a Mythos-class model
# (fable/mythos in model.id), nothing otherwise — a pure "special model" flag,
# blank at the baseline like the mode icon. ANSI magenta — slot 5, not a fixed
# 256 index — so it renders through the terminal theme (nebelung maps it to pink
# #f2c4e5). It rides the RIGHT-edge tail group (ctx% · cost · mode), NOT the
# row-1 bullet: model is per-SESSION (each ⌘C pane is its own session; --model /
# mid-session /model switches), a per-pane constant that pairs naturally with
# the other per-pane chips — and it frees the bullet to carry the worktree's git
# status. Per-pane by design: any global surface (a rewritten custom-theme file)
# would lie in a mixed-model fleet. Tried, reverted.
MODEL=""
case "$(j '.model.id')" in
  *fable*|*mythos*) MODEL=$'\033[35m'"✦${R}";;
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
# (gh-free in the render path) so a merged PR lights the ⏏ too; row 1 shows the
# icon without the PR number.
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

# --- ROW 1 : status-as-bullet + name (no repo name, no "clean") ----------------
# The git-status token IS the leading glyph: ⏏ landed / N^ ahead / +A -D dirty,
# colored by state. A worktree almost always has one (a fresh checkout at main
# is already ⏏); when nothing differs the token is empty, so fall back to a
# muted ● (clean / at-main). The model glyph used to sit here — it moved to the
# tail (per-pane, next to ctx%/cost/mode).
st=$(render_status "$ahead" "$files" "$ins" "$del" "$own_pr" "$purge")
lead="$st"; [ -z "$lead" ] && lead="${DOT}●${R}"
if [ "$is_wt" = 1 ]; then
  row1="${lead} ${NAME}${wt_name}${R}"
elif [ -n "$branch" ]; then
  row1="${lead} ${NAME}${branch}${R}"
else
  row1="${lead} ${DIM}$(basename "$cwd")${R}"
fi

# Mode icon: Claude Code's own glyph language (⏸ plan, ⏵⏵ armed), our palette.
# default/unknown stays blank — quiet is the baseline, the icon marks the
# armed/special modes. Pairs with the rice's de-footered claude build (the
# stock "⏵⏵ auto mode on (shift+tab to cycle)" row is patched out).
mseg=""
case "$mode" in
  auto)              mseg="$(c 179)⏵⏵${R}";;   # yellow — asks via classifier
  acceptEdits)       mseg="${ADD}⏵⏵${R}";;     # green  — edits sail through
  plan)              mseg="${AHEAD}⏸${R}";;    # blue   — paused to plan
  dontAsk)           mseg="${DEL}⊘${R}";;      # red    — deny-if-not-allowed
  bypassPermissions) mseg="${DEL}⏵⏵${R}";;     # red    — no gates at all
esac

# Tail group (ctx% · cost · mode icon · model) sits flush RIGHT, next to Claude
# Code's own right-edge chips (/rc); RESERVE leaves them room. Narrow pane →
# fall back to the old inline append. wc -m under a UTF-8 locale counts the wide
# glyphs as characters (≈ columns), not bytes. The model glyph, when present
# (Fable/Mythos only), is last — nearest /rc.
vlen() { plain "$1" | LC_ALL=en_US.UTF-8 wc -m | tr -d ' '; }
RESERVE=8
tailseg=""
[ -n "$ctx" ]  && tailseg="${DIM}${ctx}%${R}"
[ -n "$cost" ] && [ "$cost" != "0" ] && tailseg="${tailseg:+$tailseg }${DIM}\$$(printf '%.2f' "$cost" 2>/dev/null)${R}"
[ -n "$mseg" ] && tailseg="${tailseg:+$tailseg }$mseg"
[ -n "$MODEL" ] && tailseg="${tailseg:+$tailseg }$MODEL"
if [ -n "$tailseg" ]; then
  pad=$(( COLS - RESERVE - $(vlen "$row1") - $(vlen "$tailseg") ))
  if [ "$pad" -ge 3 ]; then
    row1="$row1$(printf '%*s' "$pad" '')$tailseg"
  else
    row1="$row1   $tailseg"
  fi
fi
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
  pst=$(render_status "$pahead" "$pfiles" "$pins" "$pdel" "$ppr" 0)
  prseg=$(render_pr "$ppr")
  repo="${pslug##*/}"
  # width-aware truncation: only clip the name if the row would exceed COLS
  stplain=$(plain "$pst"); stlen=${#stplain}
  prplain=$(plain "$prseg"); prlen=${#prplain}
  [ "$prlen" -gt 0 ] && prlen=$((prlen+1))    # trailing space after "#N"
  budget=$(( COLS - 4 - ${#repo} - 1 - prlen - stlen - 4 ))
  [ "$budget" -lt 8 ] && budget=8
  disp="$pname"
  [ ${#disp} -gt "$budget" ] && disp="${disp:0:budget-1}…"
  printf '%b\n' "  ${GRAY}○${R} ${DIM}${repo}${R} ${prseg:+$prseg }${disp}${pst:+  $pst}"
  shown=$((shown+1))
done <"$PANEL"
[ "$extra" -gt 0 ] && printf '%b\n' "  ${DIM}+${extra} more${R}"
exit 0
