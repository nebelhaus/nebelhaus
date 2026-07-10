#!/bin/bash
# pounce: name = Nix Config
# pounce: description = Open in editor
# pounce: icon = snowflake
# Open the nix config directory in the rice editor (nebelhaus.hearth.editor) —
# a new zellij tab, the same launcher the file-association hijack uses.
exec "$HOME/.config/zellij/editor-open-pane.sh" "$HOME/.config/nix"
