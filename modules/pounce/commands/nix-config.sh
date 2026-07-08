#!/bin/bash
# pounce: name = Nix Config
# pounce: description = Open in editor
# pounce: icon = snowflake
# Open the nix config directory in your editor. GUI_EDITOR below is baked from
# nebelhaus.hearth.guiEditor at build time: "hx"/"helix" opens it in a new Helix
# terminal tab (the default), a bundle id / .app name opens a GUI app, empty
# falls back to Finder.
NIX_CONFIG_DIR="$HOME/.config/nix"
GUI_EDITOR="@guiEditor@"

case "$GUI_EDITOR" in
    hx | helix)
        # New zellij tab running Helix, same launcher the file-association uses.
        exec "$HOME/.config/zellij/helix-open-pane.sh" "$NIX_CONFIG_DIR"
        ;;
    "")
        open "$NIX_CONFIG_DIR"
        ;;
    *)
        # Bundle id first, then .app name, then Finder.
        open -b "$GUI_EDITOR" "$NIX_CONFIG_DIR" 2>/dev/null ||
            open -a "$GUI_EDITOR" "$NIX_CONFIG_DIR" 2>/dev/null ||
            open "$NIX_CONFIG_DIR"
        ;;
esac
