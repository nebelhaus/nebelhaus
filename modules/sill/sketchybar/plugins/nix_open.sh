#!/bin/bash
# Open the nix config in a GUI editor. @guiEditor@ is substituted from
# nebelhaus.hearth.guiEditor at build time (empty = none configured).

TARGET="$HOME/.config/nix"
GUI_EDITOR="@guiEditor@"

# Configured GUI editor first (bundle id or app name), then the cursor/code
# CLIs if present, then Finder.
if [ -n "$GUI_EDITOR" ] && { open -b "$GUI_EDITOR" "$TARGET" 2>/dev/null || open -a "$GUI_EDITOR" "$TARGET" 2>/dev/null; }; then
    exit 0
elif command -v cursor &>/dev/null; then
    cursor "$TARGET"
elif command -v code &>/dev/null; then
    code "$TARGET"
else
    open "$TARGET"
fi
