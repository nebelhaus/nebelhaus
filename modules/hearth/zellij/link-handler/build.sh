#!/bin/bash
# Rebuilds the zellij-link-handler WASM plugin.
#
# Usage:
#   ./build.sh
#
# Requirements:
#   - Rust and Cargo installed (either natively or via Nix)
#   - wasm32-wasip1 target installed: `rustup target add wasm32-wasip1`

set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "Building zellij-link-handler WASM plugin..."
cd "$DIR"

# Ensure wasm32-wasip1 target is added if running under rustup
if command -v rustup &>/dev/null; then
  rustup target add wasm32-wasip1
fi

cargo build --target wasm32-wasip1 --release

echo "Copying compiled plugin to zellij plugins folder..."
mkdir -p ../plugins
cp target/wasm32-wasip1/release/zellij_link_handler.wasm ../plugins/zellij_link_handler.wasm

echo "Done!"
