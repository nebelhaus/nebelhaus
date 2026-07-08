#!/bin/bash
set -euo pipefail

# Claude Code on the web boots a bare Linux container with no Nix. The whole
# nebelhaus stack is a Nix flake, so without this the agent can't regenerate
# flake.lock, evaluate a host, or run `haus`. Install Nix once at session start
# and persist it for the rest of the session.
#
# Local (macOS) sessions already run Determinate Nix — do nothing there.
if [ "${CLAUDE_CODE_REMOTE:-}" != "true" ]; then
  exit 0
fi

# Install Nix if it isn't here yet. Idempotent: the container is cached after
# the first run, so re-runs (resume/clear/compact) skip straight through.
# Determinate's installer matches the rice ("Determinate owns the nix daemon");
# --init none is the container-safe, daemonless mode.
if ! command -v nix &>/dev/null && [ ! -x /nix/var/nix/profiles/default/bin/nix ]; then
  echo "Installing Nix via DeterminateSystems installer..."
  curl --proto '=https' --tlsv1.2 -sSf -L https://install.determinate.systems/nix \
    | sh -s -- install linux \
      --no-confirm \
      --init none
fi

# Source Nix into the current shell environment.
if [ -e /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh ]; then
  # shellcheck disable=SC1091
  . /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh
fi

# Persist PATH for the session so subsequent Claude tool calls can find nix.
echo "export PATH=\"/nix/var/nix/profiles/default/bin:\$PATH\"" >> "$CLAUDE_ENV_FILE"

# Nix's own fetcher (flake inputs from github/cache.nixos.org) tunnels through
# the agent proxy, which re-terminates TLS — point Nix at the proxy CA or every
# fetch fails verification.
if [ -f /root/.ccr/ca-bundle.crt ]; then
  echo "export NIX_SSL_CERT_FILE=/root/.ccr/ca-bundle.crt" >> "$CLAUDE_ENV_FILE"
fi

echo "Nix $(nix --version) ready."
