#!/bin/bash
# Open the nix config in the rice editor (nebelhaus.hearth.editor) — a new
# zellij tab, the same launcher the file-association hijack uses.
exec "$HOME/.config/zellij/editor-open-pane.sh" "$HOME/.config/nix"
