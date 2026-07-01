#!/usr/bin/env bash
# nebelhaus bootstrap — raise the house on a fresh Mac.
#
#   curl -fsSL https://raw.githubusercontent.com/nebelhaus/nebelhaus/main/bootstrap.sh | bash
#
# Idempotent: installs prerequisites (Xcode CLT, Determinate Nix), clones the
# repo, and hands you the exact rebuild command scoped to THIS machine. It never
# rebuilds a config that isn't yours — you personalize a host file first.
set -euo pipefail

REPO="${NEBELHAUS_REPO:-https://github.com/nebelhaus/nebelhaus.git}"
DEST="${NEBELHAUS_DIR:-$HOME/.config/nebelhaus}"
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
NIX="$(command -v nix || echo /nix/var/nix/profiles/default/bin/nix)"

# 3. Clone (or update).
if [ -d "$DEST/.git" ]; then
  say "Updating existing clone at $DEST"
  git -C "$DEST" pull --ff-only || warn "couldn't fast-forward; leaving as-is"
else
  say "Cloning nebelhaus → $DEST"
  git clone "$REPO" "$DEST"
fi
cd "$DEST"

# 4. Personalize: give this machine its own host file if it doesn't have one.
if [ ! -e "hosts/$HOSTNAME/default.nix" ]; then
  say "Creating hosts/$HOSTNAME from the example"
  cp -R hosts/example "hosts/$HOSTNAME"
fi

cat <<EOF

$(say "Almost there. Two steps to make it yours:")

  1. Register your host in flake.nix (under darwinConfigurations):

       darwinConfigurations.$HOSTNAME = mkNebelhaus {
         username = "$USERNAME";
         hostname = "$HOSTNAME";
         host = ./hosts/$HOSTNAME;
       };

  2. Edit hosts/$HOSTNAME/default.nix (apps, pounce signing identity, your
     shell/terminal layer), then raise the house:

       nix build .#darwinConfigurations.$HOSTNAME.system \\
         && sudo ./result/sw/bin/darwin-rebuild switch --flake .#$HOSTNAME

  Build first, switch second — a failed build never touches a running system.

EOF
