#!/usr/bin/env bash
# haus — the everyday CLI for a nebelhaus machine, so you never memorise the Nix
# incantations. This is the END-USER haus that ships in the rice (den puts it on
# PATH). It drives your OWN machine only — it knows nothing about the workshop
# family repos or agent worktrees (that's the workshop's developer CLI, `bench`).
#
#   haus rebuild        build + switch this machine from your config (the usual day)
#   haus update         pull the latest nebelhaus rice, then rebuild
#   haus rollback [N]    go back a generation (or to generation N)
#   haus generations     list the generations you can roll back to
#   haus status          current generation + how old your pinned rice is
#   haus edit            open your host config (identity, apps) in $EDITOR
#   haus doctor          check the machine's health (Nix, CLT, the GUI agents)
#   haus tour            take the guided haus tour (it lives in the bar)
set -euo pipefail

# A bare/sudo/login-item shell may have almost nothing on PATH; make sure the
# tools we call (nix, darwin-rebuild, jq, git) resolve wherever we're invoked.
PATH="/run/current-system/sw/bin:/nix/var/nix/profiles/default/bin:/etc/profiles/per-user/$(id -un)/bin:/usr/bin:/bin:/usr/sbin:/sbin:${PATH:-}"
export PATH

# Your config flake — the thin consumer with your host file, scaffolded by the
# bootstrap. Override with HAUS_CONSUMER if it lives elsewhere.
CONSUMER="${HAUS_CONSUMER:-$HOME/.config/nix}"

say()  { printf '\033[38;5;103m🌫  %s\033[0m\n' "$*"; }
warn() { printf '\033[38;5;179m⚠  %s\033[0m\n' "$*"; }
die()  { printf '\033[38;5;167m✗  %s\033[0m\n' "$*" >&2; exit 1; }
ok()   { printf '  \033[38;5;108m✓\033[0m %s\n' "$*"; }
bad()  { printf '  \033[38;5;167m✗\033[0m %s\n' "$*"; }

[ -e "$CONSUMER/flake.nix" ] || die "no config flake at $CONSUMER — set HAUS_CONSUMER, or run the bootstrap first."

SYSPROFILES=/nix/var/nix/profiles

usage() {
  cat <<'EOF'
haus — the everyday CLI for a nebelhaus machine.

  haus rebuild        build + switch this machine from your config
  haus update         pull the latest nebelhaus rice, then rebuild
  haus rollback [N]   go back a generation (or to generation N)
  haus generations    list the generations you can roll back to
  haus status         current generation + how old your pinned rice is
  haus edit           open your host config in $EDITOR
  haus doctor         check the machine's health (Nix, CLT, the GUI agents)
  haus tour           take the guided haus tour (haus tour reset re-arms it)
EOF
}

# The running system's generation number — read from the profile symlink so it
# needs no sudo (darwin-rebuild --list-generations write-locks the profile).
current_gen() {
  local link
  link="$(readlink "$SYSPROFILES/system" 2>/dev/null)" || return 1
  link="${link#system-}"
  echo "${link%-link}"
}
gen_date() { date -r "$(stat -f %m "$SYSPROFILES/system-$1-link" 2>/dev/null || echo 0)" "${2:-+%Y-%m-%d}" 2>/dev/null || echo '?'; }

host_name() { # the darwinConfiguration to build — the one host in your flake
  if [ -n "${HAUS_HOST:-}" ]; then echo "$HAUS_HOST"; return; fi
  nix eval --json "$CONSUMER#darwinConfigurations" --apply builtins.attrNames 2>/dev/null \
    | jq -r '.[0]' 2>/dev/null \
    | grep . \
    || { scutil --get LocalHostName 2>/dev/null || hostname -s; }
}

cmd_rebuild() {
  local host; host="$(host_name)"
  say "building $host from $CONSUMER …"
  # Build first, switch second: a failed build never touches a running system.
  ( cd "$CONSUMER" && nix build ".#darwinConfigurations.$host.system" ) \
    || die "build failed — nothing was changed."
  say "switching …"
  ( cd "$CONSUMER" && sudo ./result/sw/bin/darwin-rebuild switch --flake ".#$host" )
  say "the house stands."
}

cmd_update() {
  local old new owner repo subjects
  old="$(jq -r '.nodes.nebelhaus.locked.rev // ""' "$CONSUMER/flake.lock" 2>/dev/null || true)"
  say "pulling the latest nebelhaus rice …"
  ( cd "$CONSUMER" && nix flake update nebelhaus )
  new="$(jq -r '.nodes.nebelhaus.locked.rev // ""' "$CONSUMER/flake.lock" 2>/dev/null || true)"
  if [ -n "$old" ] && [ "$old" = "$new" ]; then
    say "already at the latest rice (${new:0:12}) — rebuilding anyway."
  elif [ -n "$old" ] && [ -n "$new" ]; then
    # Show what's about to land. Best-effort via the GitHub compare API —
    # offline, rate-limited, or non-GitHub upstreams just skip the list.
    owner="$(jq -r '.nodes.nebelhaus.original.owner // "nebelhaus"' "$CONSUMER/flake.lock")"
    repo="$(jq -r '.nodes.nebelhaus.original.repo // "nebelhaus"' "$CONSUMER/flake.lock")"
    subjects="$(curl -fsSL --max-time 5 \
      -H 'accept: application/vnd.github+json' \
      "https://api.github.com/repos/$owner/$repo/compare/$old...$new" 2>/dev/null \
      | jq -r '.commits[]?.commit.message | split("\n")[0]' 2>/dev/null | head -15 || true)"
    if [ -n "$subjects" ]; then
      say "new in the rice (${old:0:7} → ${new:0:7}):"
      printf '%s\n' "$subjects" | sed 's/^/  · /'
    fi
  fi
  cmd_rebuild
}

cmd_rollback() {
  if [ -n "${1:-}" ]; then
    say "switching to generation $1 …"
    sudo darwin-rebuild --switch-generation "$1"
  else
    say "rolling back to the previous generation …"
    sudo darwin-rebuild --rollback
  fi
  say "rolled back. (Nix reverts everything IT manages; macOS system settings and"
  warn "Homebrew apps are not rewound — see haus status / your notes.)"
}

cmd_generations() {
  local cur link num nums total show; cur="$(current_gen || echo '')"
  nums="$(for link in "$SYSPROFILES"/system-*-link; do
    [ -e "$link" ] || continue
    num="$(basename "$link")"; num="${num#system-}"; echo "${num%-link}"
  done | sort -rn)"
  total="$(echo "$nums" | grep -c .)"
  show=20
  # Newest first, capped — the recent ones are what you roll back to.
  echo "$nums" | head -n "$show" | while read -r num; do
    printf '%s %5s   %s\n' "$([ "$num" = "$cur" ] && echo '→' || echo ' ')" "$num" "$(gen_date "$num" '+%Y-%m-%d %H:%M')"
  done
  [ "$total" -gt "$show" ] && say "… and $((total - show)) older (roll back to any with: haus rollback <N>)"
  return 0
}

cmd_status() {
  local host lockrev lockdate url owner repo ref remoterev
  host="$(host_name)"
  say "this machine: $host"

  echo
  say "current generation"
  local cur; cur="$(current_gen || echo '')"
  if [ -n "$cur" ]; then printf '  %s  (%s)\n' "$cur" "$(gen_date "$cur")"
  else warn "  (none yet — haus rebuild)"; fi

  echo
  say "pinned nebelhaus rice"
  if [ -f "$CONSUMER/flake.lock" ]; then
    lockrev="$(jq -r '.nodes.nebelhaus.locked.rev // "?"' "$CONSUMER/flake.lock")"
    lockdate="$(jq -r '.nodes.nebelhaus.locked.lastModified // 0' "$CONSUMER/flake.lock")"
    if [ "$lockdate" != "0" ]; then
      printf '  %s  (%s)\n' "${lockrev:0:12}" "$(date -r "$lockdate" '+%Y-%m-%d' 2>/dev/null || echo '?')"
    else
      printf '  %s\n' "${lockrev:0:12}"
    fi
    # Is the upstream rice ahead of what you've pinned? Best-effort, offline-safe.
    owner="$(jq -r '.nodes.nebelhaus.original.owner // "nebelhaus"' "$CONSUMER/flake.lock")"
    repo="$(jq -r '.nodes.nebelhaus.original.repo // "nebelhaus"' "$CONSUMER/flake.lock")"
    ref="$(jq -r '.nodes.nebelhaus.original.ref // "HEAD"' "$CONSUMER/flake.lock")"
    url="https://github.com/$owner/$repo.git"
    remoterev="$(git ls-remote "$url" "$ref" 2>/dev/null | awk 'NR==1{print $1}')"
    if [ -n "$remoterev" ] && [ "$remoterev" != "$lockrev" ]; then
      warn "  a newer rice is available upstream (${remoterev:0:12}) — haus update"
    elif [ -n "$remoterev" ]; then
      ok "up to date with upstream"
    fi
  else
    warn "  no flake.lock yet"
  fi
}

cmd_edit() {
  local host f
  host="$(host_name)"
  f="$CONSUMER/hosts/$host/default.nix"
  [ -f "$f" ] || die "no host file at $f"
  exec "${EDITOR:-hx}" "$f"
}

cmd_doctor() {
  local uid; uid="$(id -u)"
  say "nebelhaus doctor"

  # Determinate Nix (den assumes it owns the daemon: nix.enable = false).
  if [ -f /nix/receipt.json ]; then ok "Determinate Nix installed"
  elif [ -d /nix ]; then bad "/nix exists but not Determinate — nebelhaus expects the Determinate installer"
  else bad "Nix not installed"; fi
  pgrep -qx nix-daemon && ok "nix-daemon running" || bad "nix-daemon not running"

  # Xcode CLT (pounce compiles against system Swift; git comes from here too).
  /usr/bin/xcode-select -p >/dev/null 2>&1 && ok "Xcode Command Line Tools" || bad "Xcode CLT missing — xcode-select --install"

  command -v darwin-rebuild >/dev/null 2>&1 && ok "darwin-rebuild on PATH" || bad "darwin-rebuild missing — has this machine switched yet?"

  # GUI agents — only report on the ones whose launchd plist exists (i.e. the
  # rooms you enabled). Running is good; stopped may just mean the room is off.
  echo
  say "GUI agents"
  local label name
  for pair in "org.nixos.aerospace:AeroSpace" "org.nixos.sketchybar:sketchybar" "org.nixos.pounce:pounce"; do
    label="${pair%%:*}"; name="${pair##*:}"
    if launchctl print "gui/$uid/$label" >/dev/null 2>&1; then
      if pgrep -qx "$name"; then ok "$name running"
      else bad "$name enabled but not running — check /tmp/$name.err.log (a wedged cold-boot agent: launchctl kickstart -k gui/$uid/$label)"; fi
    fi
  done

  # Accessibility grant — pounce's auto-paste and emoji insertion need it, and a
  # missing grant is the #1 "why won't paste work" gotcha. Only meaningful when
  # pounce is enabled (its launchd plist exists).
  if launchctl print "gui/$uid/org.nixos.pounce" >/dev/null 2>&1; then
    echo
    say "Accessibility"
    if command -v pounce >/dev/null 2>&1 && [ "$(pounce --check-accessibility 2>/dev/null)" = "true" ]; then
      ok "pounce has Accessibility (auto-paste + emoji work)"
    else
      bad "pounce is missing Accessibility — grant once: pounce --request-accessibility"
    fi
  fi

  # Homebrew casks aren't tracked by Nix generations, so a rollback can't rewind
  # them and undeclared casks linger. Flag the drift so it isn't a silent gap.
  if command -v brew >/dev/null 2>&1; then
    echo
    say "Homebrew"
    ok "brew on PATH ($(brew list --cask 2>/dev/null | grep -c . ) casks installed)"
    warn "casks aren't in Nix generations — 'haus rollback' won't rewind them (brew uninstall --zap <cask>)"
  fi

  # Secrets — the declaration (secretspec.toml) rebuilds with Nix, but the
  # VALUES live in the provider and may need entering once per machine.
  echo
  say "Secrets"
  if command -v secretspec >/dev/null 2>&1; then
    local provider
    provider="$(sed -n 's/^provider *= *"\(.*\)"/\1/p' "$HOME/.config/secretspec/config.toml" 2>/dev/null | head -1)"
    if [ -n "$provider" ]; then ok "secretspec on PATH (default provider: $provider)"
    else warn "no default provider — set nebelhaus.secrets.provider, or run: secretspec config init"; fi
    # If your config flake declares secrets, verify their values are present.
    # </dev/null keeps check from prompting; missing values are for `set`.
    if [ -f "$CONSUMER/secretspec.toml" ]; then
      if (cd "$CONSUMER" && secretspec check </dev/null >/dev/null 2>&1); then
        ok "all secrets in $CONSUMER/secretspec.toml have values"
      else
        bad "missing secret values — run: cd $CONSUMER && secretspec check"
      fi
    fi
  else
    bad "secretspec missing — 'haus rebuild' installs it (the secrets room)"
  fi
}

# The tour itself is the bar's tour.sh (sill ships it; see modules/sill) —
# haus is just the terminal-shaped door to it, for the user who read the
# bootstrap's closing line instead of spotting the pill.
cmd_tour() {
  local plugin="$HOME/.config/sketchybar/plugins/tour.sh"
  [ -x "$plugin" ] || die "the tour lives in the bar — it needs the sill + prowl rooms enabled."
  case "${1:-start}" in
    start) "$plugin" start && say "the tour is in the bar — follow the paw, top right." ;;
    reset) "$plugin" reset && say "tour re-armed — the dormant hint is back in the bar." ;;
    *)     die "unknown tour subcommand '$1' — try: haus tour [start|reset]" ;;
  esac
}

case "${1:-status}" in
  rebuild)     cmd_rebuild ;;
  update)      cmd_update ;;
  rollback)    cmd_rollback "${2:-}" ;;
  generations) cmd_generations ;;
  status)      cmd_status ;;
  edit)        cmd_edit ;;
  doctor)      cmd_doctor ;;
  tour)        cmd_tour "${2:-}" ;;
  -h|--help|help) usage ;;
  *)           die "unknown command '$1' — try: rebuild update rollback generations status edit doctor tour" ;;
esac
