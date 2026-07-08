#!/bin/bash
# Open the nix config in your editor. GUI_EDITOR below is baked from
# nebelhaus.hearth.guiEditor at build time: "hx"/"helix" opens it in a new Helix
# terminal tab (the default), a bundle id / .app name opens a GUI app, empty
# falls back to Finder.
TARGET="$HOME/.config/nix"
GUI_EDITOR="@guiEditor@"

case "$GUI_EDITOR" in
    hx | helix)
        # New zellij tab running Helix, same launcher the file-association uses.
        exec "$HOME/.config/zellij/helix-open-pane.sh" "$TARGET"
        ;;
    "")
        open "$TARGET"
        ;;
    *)
        # Bundle id first, then .app name, then Finder.
        open -b "$GUI_EDITOR" "$TARGET" 2>/dev/null ||
            open -a "$GUI_EDITOR" "$TARGET" 2>/dev/null ||
            open "$TARGET"
        ;;
esac
