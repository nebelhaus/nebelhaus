#!/bin/zsh

# Open a file OR a directory in Helix, in a new zellij tab. Called by the
# HelixOpen.app file-association handler (a file) and by the "Nix Config"
# palette/bar commands (a directory).
FILE_PATH="${1:A}"

# 1. Ensure Ghostty is running
if ! pgrep -x "Ghostty" > /dev/null; then
    open -a "Ghostty"
    # Wait for Ghostty and Zellij to bootstrap
    sleep 2.0
fi

# 2. Check if the "main" zellij session is active
if ! zellij list-sessions 2>/dev/null | grep -q "main"; then
    # Wait up to 5 seconds for the session to appear
    for i in {1..10}; do
        sleep 0.5
        if zellij list-sessions 2>/dev/null | grep -q "main"; then
            break
        fi
    done
fi

# A directory opens as `hx .` cwd'd into it; a file opens cwd'd into its parent.
if [ -d "$FILE_PATH" ]; then
    DIR_PATH="$FILE_PATH"
    TARGET="."
else
    DIR_PATH="$(dirname "$FILE_PATH")"
    TARGET="$FILE_PATH"
fi

# 3. Open in a new tab with zsh and helix
if zellij list-sessions 2>/dev/null | grep -q "main"; then
    # Focus Ghostty to bring it to front
    osascript -e 'tell application "Ghostty" to activate'

    # Open in a new tab running zsh, cd to the dir, run helix, and exec zsh on exit
    zellij -s main action new-tab -- zsh -c 'cd "$1" && hx "$2"; exec zsh' "helix-launcher" "$DIR_PATH" "$TARGET"
else
    # Fallback: Open a fresh Ghostty window running helix on the target
    open -na "Ghostty" --args -e "hx \"$FILE_PATH\""
fi
