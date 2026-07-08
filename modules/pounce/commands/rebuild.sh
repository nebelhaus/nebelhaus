#!/bin/bash
# pounce: name = Rebuild System
# pounce: description = Rebuild nix configuration
# pounce: icon = arrow.triangle.2.circlepath
# Rebuild nix system configuration in a small centered ghostty window.
#
# Host-agnostic: `@hostname@` is substituted at build time by modules/pounce
# (from mkNebelhaus's hostname), and the flake lives at ~/.config/nix by
# convention — override with $NEBELHAUS_FLAKE if yours is elsewhere.
#
# The floating window is spawned by the shared float-term helper
# (hearth/zellij/float-term.sh) — the single implementation of the macOS
# "fresh Ghostty instance → PID-diff → AppleScript-settle → aerospace-float"
# dance, reused by peek and the agent-peek popup too. This command's only job
# is to build the host-specific rebuild payload and hand it off.

FLOAT_TERM="$HOME/.config/zellij/float-term.sh"
WINDOW_TITLE="quick-terminal-rebuild"

# Stable temp path so we don't need to thread a multiline script through
# `open --args`. Overwritten on every invocation.
REBUILD_TMP="/tmp/nix-rebuild-run.sh"
cat >"$REBUILD_TMP" <<'EOF'
#!/bin/bash
export PATH="/run/current-system/sw/bin:/nix/var/nix/profiles/default/bin:$PATH"

cd "${NEBELHAUS_FLAKE:-$HOME/.config/nix}" || exit 1

echo "Building nix configuration..."
echo ""

if nix build ".#darwinConfigurations.@hostname@.system"; then
    echo ""
    echo "Build successful. Switching..."
    echo ""
    if sudo ./result/sw/bin/darwin-rebuild switch --flake ".#@hostname@"; then
        echo ""
        echo "✓ System rebuild complete!"
    else
        echo ""
        echo "✗ Switch failed"
    fi
else
    echo ""
    echo "✗ Build failed"
fi

echo ""
echo "Press any key to close..."
read -n 1 -s
EOF
# Defensive: strip quarantine xattr so macOS Gatekeeper doesn't prompt.
xattr -d com.apple.quarantine "$REBUILD_TMP" 2>/dev/null || true

# A small (750×400px / ~80×20-cell) window, centered on the cursor's screen and
# pinned to the current workspace. --command overrides the ghostty config's
# default zellij launcher so this instance only ever runs the rebuild payload.
"$FLOAT_TERM" spawn \
  --title "$WINDOW_TITLE" \
  --w 750 --h 400 --cols 80 --rows 20 \
  --pin \
  --command "bash $REBUILD_TMP" >/dev/null
