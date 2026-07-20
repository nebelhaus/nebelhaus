#!/usr/bin/env bash
# statusline-refresh.sh — the EXPENSIVE half of the nebelhaus statusline.
#
# Enumerates every in-flight agent worktree across ALL repos (via `wt`'s
# registry) and, per repo, asks GitHub once for PR state. Writes a raw-field TSV
# that statusline.sh renders with the SAME status-token logic as row 1. Run
# DETACHED by statusline.sh when its cache goes stale (stale-while-revalidate) —
# never in the render path, so the bar is never blocked by git/gh. Safe to run
# concurrently: a mkdir-lock elects one refresher; the rest exit immediately.
#
#   panel.tsv rows:  slug <TAB> name <TAB> ahead <TAB> files <TAB> ins <TAB> del <TAB> prstate
#     slug    = owner/repo   (e.g. nebelhaus/pounce)
#     name    = worktree name (branch minus worktree- prefix)
#     ahead   = commits on the branch not in its default branch
#     files/ins/del = uncommitted working-tree delta (live checkouts only)
#     prstate = "#7 open" | "#7 merged" | "#7 closed" | ""
#   Only IN-FLIGHT rows are written (ahead>0, or dirty, or has a PR).
set -euo pipefail
PATH="/run/current-system/sw/bin:/nix/var/nix/profiles/default/bin:/etc/profiles/per-user/$(id -un 2>/dev/null)/bin:/opt/homebrew/bin:/usr/bin:/bin:${PATH:-}"

WT_BASE="${CLAUDE_WT_BASE:-$HOME/.cache/claude-worktrees}"
WT_REGISTRY="$WT_BASE/registry.tsv"
CACHE_DIR="${CLAUDE_STATUSLINE_CACHE:-$HOME/.cache/claude-statusline}"
PANEL="$CACHE_DIR/panel.tsv"
LOCK="$CACHE_DIR/refresh.lock"

mkdir -p "$CACHE_DIR"
# Single-refresher election: mkdir is atomic. Stale lock (>60s) is reclaimed.
if ! mkdir "$LOCK" 2>/dev/null; then
  if [ -d "$LOCK" ]; then
    age=$(( $(date +%s) - $(stat -f %m "$LOCK" 2>/dev/null || echo 0) ))
    [ "$age" -lt 60 ] && exit 0
    rmdir "$LOCK" 2>/dev/null || true
    mkdir "$LOCK" 2>/dev/null || exit 0
  else
    exit 0
  fi
fi
trap 'rmdir "$LOCK" 2>/dev/null || true' EXIT

git_default() { # default branch of a main checkout, e.g. main / master
  git -C "$1" symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null \
    | sed 's@^origin/@@' && return 0
  for b in main master; do
    git -C "$1" show-ref -q --verify "refs/heads/$b" && { echo "$b"; return 0; }
  done
  echo main
}

repo_slug() { # owner/name from a main checkout's origin remote
  local url
  url=$(git -C "$1" remote get-url origin 2>/dev/null) || return 1
  url=${url%.git}
  url=${url#*://}      # drop scheme  (https://host/… -> host/…)
  url=${url#*@}        # drop user    (git@host:…    -> host:…)
  url=${url#*[:/]}     # drop host + first separator  -> owner/name
  [ -n "$url" ] && echo "$url" || return 1
}

# --- PR lookup, one gh call per repo, cached ~120s (PR state moves slowly) ------
pr_json_for_repo() { # $1=main ; echoes cached JSON of that repo's PRs
  local main="$1" slug cache age
  slug=$(repo_slug "$main") || { echo '[]'; return; }
  cache="$CACHE_DIR/pr-$(echo "$slug" | tr '/' '_').json"
  if [ -f "$cache" ]; then
    age=$(( $(date +%s) - $(stat -f %m "$cache" 2>/dev/null || echo 0) ))
    [ "$age" -lt 120 ] && { cat "$cache"; return; }
  fi
  if gh pr list -R "$slug" --state all --limit 100 \
        --json number,state,headRefName >"$cache.tmp" 2>/dev/null; then
    mv "$cache.tmp" "$cache"
  else
    rm -f "$cache.tmp"; [ -f "$cache" ] || echo '[]' >"$cache"
  fi
  cat "$cache"
}

pr_state_for_branch() { # $1=main $2=branch -> "#N open|merged|closed" or ""
  pr_json_for_repo "$1" | jq -r --arg b "$2" '
    map(select(.headRefName == $b)) | (.[0] // empty)
    | "#\(.number) \(.state|ascii_downcase)"' 2>/dev/null
}

# --- enumerate worktrees from the registry, keep only in-flight ones ------------
: >"$PANEL.tmp"
[ -f "$WT_REGISTRY" ] || { mv "$PANEL.tmp" "$PANEL"; exit 0; }

while IFS=$'\t' read -r name main branch wtpath; do
  [ -n "${branch:-}" ] || continue
  git -C "$main" show-ref -q --verify "refs/heads/$branch" 2>/dev/null || continue
  slug=$(repo_slug "$main" || basename "$main")
  def=$(git_default "$main")
  ahead=$(git -C "$main" rev-list --count "$def..$branch" 2>/dev/null || echo 0)

  files=0 ins=0 del=0
  if [ -e "$wtpath/.git" ]; then
    files=$(git -C "$wtpath" --no-optional-locks status --porcelain 2>/dev/null | wc -l | tr -d ' ')
    if [ "$files" -gt 0 ]; then
      read -r ins del < <(git -C "$wtpath" --no-optional-locks diff HEAD --shortstat 2>/dev/null \
        | awk '{i=0;d=0;for(k=1;k<=NF;k++){if($k~/insertion/)i=$(k-1);if($k~/deletion/)d=$(k-1)}print i" "d}')
      ins=${ins:-0}; del=${del:-0}
    fi
  fi

  pr=$(pr_state_for_branch "$main" "$branch")

  # in-flight only: unmerged commits, uncommitted edits, or a PR
  [ "$ahead" -gt 0 ] || [ "$files" -gt 0 ] || [ -n "$pr" ] || continue

  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
    "$slug" "${branch#worktree-}" "$ahead" "$files" "$ins" "$del" "${pr:-}" >>"$PANEL.tmp"
done <"$WT_REGISTRY"

mv "$PANEL.tmp" "$PANEL"
