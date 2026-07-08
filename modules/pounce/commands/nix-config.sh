#!/bin/bash
# pounce: name = Nix Config
# pounce: description = Open in editor
# pounce: icon = snowflake
# Open the nix config directory in your GUI editor. @guiEditor@ is substituted
# from nebelhaus.hearth.guiEditor at build time (empty = none configured).

NIX_CONFIG_DIR="$HOME/.config/nix"
GUI_EDITOR="@guiEditor@"

# Configured GUI editor first (bundle id or app name), then the cursor/code
# CLIs if present, then Finder.
if [ -n "$GUI_EDITOR" ] && { open -b "$GUI_EDITOR" "$NIX_CONFIG_DIR" 2>/dev/null || open -a "$GUI_EDITOR" "$NIX_CONFIG_DIR" 2>/dev/null; }; then
    exit 0
elif command -v cursor &>/dev/null; then
    cursor "$NIX_CONFIG_DIR"
elif command -v code &>/dev/null; then
    code "$NIX_CONFIG_DIR"
else
    open "$NIX_CONFIG_DIR"
fi
