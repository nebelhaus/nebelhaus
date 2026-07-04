#!/usr/bin/env bash
# nebelhaus bootstrap — raise the house on a fresh Mac.
#
#   nix run github:nebelhaus/nebelhaus#bootstrap
#   # or, before nix exists:
#   curl -fsSL https://raw.githubusercontent.com/nebelhaus/nebelhaus/main/bootstrap.sh | bash
#
# It installs the prerequisites (Xcode CLT, Determinate Nix), then scaffolds a
# THIN PERSONAL CONFIG at ~/.config/nix — a tiny flake of your own that consumes
# the nebelhaus rice as an input. You never edit (or even clone) the rice repo
# itself: your machine's identity, apps, and secrets live in your config; the
# rice stays upstream where `nix flake update nebelhaus` can always pull it.
#
# Idempotent: safe to re-run. It never switches a config that isn't yours —
# you personalize the generated host file first.
set -euo pipefail

RAW="${NEBELHAUS_RAW:-https://raw.githubusercontent.com/nebelhaus/nebelhaus/main}"
DEST="${NEBELHAUS_DIR:-$HOME/.config/nix}"
USERNAME="$(id -un)"
HOSTNAME="$(scutil --get LocalHostName 2>/dev/null || hostname -s)"

say() { printf '\033[38;5;103m🌫  %s\033[0m\n' "$*"; }
warn() { printf '\033[38;5;179m⚠  %s\033[0m\n' "$*"; }

[ "$(uname)" = "Darwin" ] || { warn "nebelhaus is macOS-only."; exit 1; }

# 1. Xcode Command Line Tools (pounce compiles against system Swift via xcrun).
if ! /usr/bin/xcode-select -p >/dev/null 2>&1; then
  say "Installing Xcode Command Line Tools — approve the dialog, then re-run this."
  /usr/bin/xcode-select --install || true
  exit 0
fi

# 2. Determinate Nix.
if ! command -v nix >/dev/null 2>&1 && [ ! -x /nix/var/nix/profiles/default/bin/nix ]; then
  say "Installing Determinate Nix…"
  curl -fsSL https://install.determinate.systems/nix | sh -s -- install --determinate
  # shellcheck disable=SC1091
  . /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh
fi

# 3. Scaffold your config — unless you already have one.
if [ -e "$DEST/flake.nix" ]; then
  say "You already have a config at $DEST — leaving it alone."
else
  say "Scaffolding your personal config at $DEST"
  mkdir -p "$DEST/hosts/$HOSTNAME"

  # (This is where the interactive interview will live: a few questions —
  # editor, accent, bar style — templated into the host file below.)

  cat >"$DEST/flake.nix" <<EOF
{
  description = "$USERNAME's machine — a nebelhaus";

  # The whole rice (system + shell + pounce + nebelung) comes from the public
  # nebelhaus flake. This config holds only what's personal: the host.
  # Update everything with:  nix flake update nebelhaus
  inputs.nebelhaus.url = "github:nebelhaus/nebelhaus";

  outputs =
    { nebelhaus, ... }:
    {
      darwinConfigurations.$HOSTNAME = nebelhaus.mkNebelhaus {
        username = "$USERNAME";
        hostname = "$HOSTNAME";
        host = ./hosts/$HOSTNAME;
      };
    };
}
EOF

  # Your host file starts as the documented example from the rice.
  curl -fsSL "$RAW/hosts/example/default.nix" -o "$DEST/hosts/$HOSTNAME/default.nix"

  printf 'result\nresult-*\n' >"$DEST/.gitignore"

  if [ ! -d "$DEST/.git" ]; then
    git -C "$DEST" init -q -b main
    git -C "$DEST" add -A
    git -C "$DEST" commit -qm "Scaffold a nebelhaus consumer for $HOSTNAME" || true
  fi
fi

cat <<EOF

$(say "Almost there. Two steps to make it yours:")

  1. Edit $DEST/hosts/$HOSTNAME/default.nix — your git identity, your
     apps, the pounce signing identity (all documented inline).

  2. Raise the house:

       cd $DEST
       nix build .#darwinConfigurations.$HOSTNAME.system \\
         && sudo ./result/sw/bin/darwin-rebuild switch --flake .#$HOSTNAME

  Build first, switch second — a failed build never touches a running system.

$(say "Later: push $DEST to a private repo of your own; it's your machine in text form.")
EOF
