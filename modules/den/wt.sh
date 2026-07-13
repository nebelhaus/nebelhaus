#!/usr/bin/env bash
# wt — manage Claude Code agent worktrees, for ANY git repo.
#
# `claude --worktree` (the Super-c / ⌘C zellij bind) fires Claude Code's
# WorktreeCreate/WorktreeRemove hooks; this script is what they call. It keeps
# agent checkouts under ~/.cache/claude-worktrees/<repo>/<name> (out of the repo
# so trees stay clean) on branch worktree-<name>, and — crucially — makes
# closing a pane safe and reversible:
#
#   wt                list every parked/live agent worktree, across ALL repos
#   wt <name>         resume one: rebuild its checkout + reopen its Claude chat
#   wt resume <name>  (the same thing, spelled out)
#   wt create         [hook] make a worktree for the current repo (JSON on stdin)
#   wt remove         [hook] retire one WITHOUT losing work (JSON on stdin)
#
# This is deliberately self-contained: pure git + filesystem, no knowledge of
# any particular repo, flake, or the nebelhaus workshop's `bench`. It works for
# whatever repo you happen to be in. State lives in the registry (see below).
set -euo pipefail

# Hooks run with a bare PATH; make sure git resolves (and claude, for resume).
PATH="/run/current-system/sw/bin:/nix/var/nix/profiles/default/bin:/etc/profiles/per-user/$(id -un 2>/dev/null)/bin:/usr/bin:/bin:${PATH:-}"

WT_BASE="${CLAUDE_WT_BASE:-$HOME/.cache/claude-worktrees}"
# The registry is `wt`'s source of truth for parked worktrees: one tab-separated
# line per worktree — "name<TAB>main-checkout<TAB>branch<TAB>checkout-path" —
# written at create time. It lets `wt` rebuild a parked worktree and find its
# main checkout across ANY repo, even after the checkout dir is gone. Merged-away
# worktrees are pruned; unmerged ones linger exactly as long as their branch.
WT_REGISTRY="$WT_BASE/registry.tsv"

say() { printf '\033[38;5;103m🌫  %s\033[0m\n' "$*" >&2; }
die() { printf '\033[38;5;167m✗  %s\033[0m\n' "$*" >&2; exit 1; }

reg_put() { # reg_put <name> <main> <branch> <wt_path> — upsert, keyed on wt_path
  mkdir -p "$WT_BASE"
  local tmp="$WT_REGISTRY.$$"
  if [ -f "$WT_REGISTRY" ]; then
    awk -F'\t' -v p="$4" '$4 != p' "$WT_REGISTRY" >"$tmp"
  else
    : >"$tmp"
  fi
  printf '%s\t%s\t%s\t%s\n' "$1" "$2" "$3" "$4" >>"$tmp"
  mv "$tmp" "$WT_REGISTRY"
}

reg_del() { # reg_del <wt_path> — drop the line for a worktree we've reaped
  [ -f "$WT_REGISTRY" ] || return 0
  local tmp="$WT_REGISTRY.$$"
  awk -F'\t' -v p="$1" '$4 != p' "$WT_REGISTRY" >"$tmp"
  mv "$tmp" "$WT_REGISTRY"
}

git_main() { # git_main <dir> — the MAIN checkout backing any worktree of a repo
  dirname "$(git -C "$1" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)"
}

wt_projdir() { # wt_projdir <abs-cwd> — Claude Code's transcript dir for that cwd
  # Claude encodes the project by its cwd, replacing every '/' and '.' with '-'.
  printf '%s/.claude/projects/%s' "$HOME" "$(printf '%s' "$1" | sed 's/[/.]/-/g')"
}

hook_field() { # hook_field <json> <key>… — first key present in the payload
  # Key names drift across Claude Code versions (docs say worktree_name/base_path;
  # 2.1.x sends name/cwd) — accept either, first hit wins.
  local json="$1"
  shift
  python3 -c '
import json, sys
d = json.load(sys.stdin)
for k in sys.argv[1:]:
    if k in d:
        print(d[k]); break
else:
    print(f"hook payload has none of {sys.argv[1:]}: {d}", file=sys.stderr); sys.exit(1)
' "$@" <<<"$json"
}

cmd_create() { # [WorktreeCreate hook] JSON on stdin; ONLY the new path on stdout
  local json name base dir
  json="$(cat)"
  name="$(hook_field "$json" name worktree_name)"
  base="$(hook_field "$json" base_path cwd)"
  dir="$WT_BASE/$(basename "$base")/$name"
  git -C "$base" worktree add -b "worktree-$name" "$dir" HEAD >&2
  # Record it so `wt` can rebuild + reopen this worktree later — even after the
  # checkout is removed, and even for repos it has never otherwise heard of.
  reg_put "$name" "$(git_main "$base")" "worktree-$name" "$dir" || true
  echo "$dir"
}

cmd_remove() { # [WorktreeRemove hook] JSON on stdin — retire without losing work
  local json dir main branch
  json="$(cat)"
  dir="$(hook_field "$json" worktree_path path)"
  main="$(git_main "$dir")"
  branch="$(git -C "$dir" branch --show-current 2>/dev/null || true)"
  # A --force remove would silently discard UNCOMMITTED edits. Committed work
  # always survives on the branch; park the dirty remainder there too, as a WIP
  # commit, so closing a pane can never cost you work. gpgsign off: this hook is
  # non-interactive, and a signing prompt here would hang the whole teardown.
  if [ -n "$(git -C "$dir" status --porcelain 2>/dev/null)" ]; then
    git -C "$dir" add -A >/dev/null 2>&1 || true
    git -C "$dir" -c commit.gpgsign=false \
      commit -q -m "wip: auto-saved on pane close ($(date '+%Y-%m-%d %H:%M'))" \
      >/dev/null 2>&1 || true
  fi
  git -C "$main" worktree remove "$dir" 2>/dev/null \
    || git -C "$main" worktree remove --force "$dir"
  # The branch is how unmerged work survives; only reap it once merged (-d refuses
  # otherwise — the safety that lets unmerged work persist). Keep the registry
  # line in lockstep: gone when merged, kept while still resumable.
  if [ -n "$branch" ] && git -C "$main" branch -d "$branch" >/dev/null 2>&1; then
    reg_del "$dir"
  fi
}

# resume_rows — every resumable/live agent worktree, deduped, one per line as
# "main<TAB>branch<TAB>wt_path". Fully generic: the set of repos is discovered,
# never hardcoded. Sources: the registry (authoritative paths, survives checkout
# deletion), every live checkout on disk (glob — this is "all repos with an open
# worktree"), and orphan worktree-* branches from any main we can reach via the
# first two. First hit per (main,branch) wins, so a real path beats a rebuilt one.
resume_rows() {
  local rows="" raw="" real="" d m b mdir ob
  [ -f "$WT_REGISTRY" ] && rows+="$(awk -F'\t' 'NF>=4 {print $2"\t"$3"\t"$4}' "$WT_REGISTRY")"$'\n'
  for d in "$WT_BASE"/*/*; do
    [ -e "$d/.git" ] || continue
    m="$(git_main "$d")" || continue
    b="$(git -C "$d" branch --show-current 2>/dev/null)" || continue
    [ -n "$b" ] && rows+="$m"$'\t'"$b"$'\t'"$d"$'\n'
    raw+="$m"$'\n'
  done
  [ -f "$WT_REGISTRY" ] && raw+="$(awk -F'\t' 'NF>=2 {print $2}' "$WT_REGISTRY")"$'\n'
  # Normalize each candidate to its real main (collapsing worktree paths), keep
  # only true main checkouts (.git is a DIR, not a worktree's .git file), dedup.
  while IFS= read -r mdir; do
    [ -n "$mdir" ] || continue
    m="$(git_main "$mdir" 2>/dev/null)" || continue
    [ -n "$m" ] && [ -d "$m/.git" ] && real+="$m"$'\n'
  done <<<"$raw"
  while IFS= read -r mdir; do
    [ -n "$mdir" ] || continue
    for ob in $(git -C "$mdir" branch --list 'worktree-*' --format='%(refname:short)' 2>/dev/null); do
      rows+="$mdir"$'\t'"$ob"$'\t'"$WT_BASE/$(basename "$mdir")/${ob#worktree-}"$'\n'
    done
  done <<<"$(printf '%s' "$real" | awk 'NF && !s[$0]++')"
  printf '%s' "$rows" | awk -F'\t' 'NF>=3 && !seen[$1 FS $2]++'
}

cmd_list() {
  say "agent worktrees you can resume (wt <name>, or <repo>/<name>)"
  printf '  %-12s %-26s %-6s %-4s %s\n' "repo" "name" "state" "chat" "last commit"
  local any=0 main branch wt repo nm state chat last
  while IFS=$'\t' read -r main branch wt; do
    [ -n "$branch" ] || continue
    git -C "$main" show-ref -q --verify "refs/heads/$branch" 2>/dev/null || continue
    any=1
    repo="$(basename "$main")"
    nm="${branch#worktree-}"
    [ -e "$wt/.git" ] && state="live" || state="parked"
    [ -d "$(wt_projdir "$wt")" ] && chat="yes" || chat="·"
    last="$(git -C "$main" log -1 --format='%cr — %s' "$branch" 2>/dev/null)"
    printf '  %-12s %-26s %-6s %-4s %s\n' "$repo" "$nm" "$state" "$chat" "${last:0:56}"
  done <<<"$(resume_rows)"
  [ "$any" = "1" ] || say "none parked — every worktree branch is merged & cleaned up. The fog is even."
}

cmd_resume() { # cmd_resume <name|repo/name>
  local want="${1:-}"
  [ -n "$want" ] || { cmd_list; return 0; }
  local rrepo="" rname="$want" sel="" matches=0 main branch wt
  case "$want" in */*) rrepo="${want%%/*}"; rname="${want##*/}" ;; esac
  while IFS=$'\t' read -r main branch wt; do
    [ -n "$branch" ] || continue
    git -C "$main" show-ref -q --verify "refs/heads/$branch" 2>/dev/null || continue
    [ "${branch#worktree-}" = "$rname" ] || continue
    [ -z "$rrepo" ] || [ "$(basename "$main")" = "$rrepo" ] || continue
    sel="$main"$'\t'"$branch"$'\t'"$wt"
    matches=$((matches + 1))
  done <<<"$(resume_rows)"

  [ "$matches" = "0" ] && die "no agent worktree named '$want' — run: wt"
  [ "$matches" -gt 1 ] && die "'$rname' exists in more than one repo — qualify it: wt <repo>/$rname"

  IFS=$'\t' read -r main branch wt <<<"$sel"
  if [ -e "$wt/.git" ]; then
    say "'$branch' is still live at $wt"
  else
    say "rebuilding checkout for $branch → $wt"
    mkdir -p "$(dirname "$wt")"
    git -C "$main" worktree add "$wt" "$branch" >&2
    reg_put "${branch#worktree-}" "$main" "$branch" "$wt" || true
  fi
  if [ -t 1 ] && command -v claude >/dev/null 2>&1; then
    say "reopening the chat (same cwd → same transcript) …"
    cd "$wt" && exec claude --resume
  else
    say "checkout ready. Reopen the chat with:"
    printf '    cd %q && claude --resume\n' "$wt"
  fi
}

case "${1:-}" in
create) cmd_create ;;
remove) cmd_remove ;;
resume) cmd_resume "${2:-}" ;;
list | ls) cmd_list ;;
"" | -h | --help | help) [ "${1:-}" = "" ] && cmd_list || sed -n '2,20p' "$0" | sed '/^#!/d; s/^# \{0,1\}//' ;;
*) cmd_resume "$1" ;; # bare token → treat as a worktree name to resume
esac
