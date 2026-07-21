#!/bin/bash
# Rebuilds the zellij-link-handler WASM plugin (nix cross-build, no rustup
# needed) and vendors it into ../plugins/ where hearth picks it up.
#
# Usage:
#   ./build.sh
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$DIR"

echo "Building zellij-link-handler WASM plugin (pkgsCross.wasi32)..."
nix build --impure --expr \
  '(builtins.getFlake "nixpkgs").legacyPackages.${builtins.currentSystem}.pkgsCross.wasi32.callPackage ./default.nix {}'

echo "Copying compiled plugin to zellij plugins folder..."
cp -f result/bin/zellij-link-handler.wasm ../plugins/zellij_link_handler.wasm
rm result

echo "Done!"
