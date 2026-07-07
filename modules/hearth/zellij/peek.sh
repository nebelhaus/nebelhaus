#!/bin/bash
# peek.sh — spawn a native, floating Ghostty window running Yazi.
#
# Since this runs outside Zellij, the image previews are perfectly crisp and
# support Kitty graphics. AeroSpace detects the window title and floats it
# on the current workspace automatically. When Yazi exits, the window closes.

set -eu

# Trigger a native Ghostty window running yazi, inheriting current directory
open -na Ghostty --args --title="peek" --working-directory="$PWD" -e yazi
