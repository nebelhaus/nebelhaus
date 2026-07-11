#!/bin/bash
# navigate_mode.sh on|off
#
# Indicator for AeroSpace's `navigate` mode (entered by tapping caps then an
# arrow key). Recolors the front-app pill catppuccin sky and appends a four-way
# arrows glyph to the app name. `off` restores the normal lavender pill and the
# bare app name. Mirrors resize_mode.sh.
#
# Navigate mode is all about moving focus, so focusing another window fires
# front_app_switched and repaints the label. A state file (STATE) records that
# the mode is armed: front_app.sh reads it so the glyph survives those repaints
# instead of being dropped (the same trick resize mode uses).

export PATH="/run/current-system/sw/bin:/opt/homebrew/bin:/usr/bin:/bin:$PATH"

STATE="/tmp/sketchybar_navigate_state"   # present == armed

source "$HOME/.config/sketchybar/colors.sh"

# fa-arrows (U+F047) as raw UTF-8 bytes — /bin/bash is 3.2, whose printf has
# no \u/\U; \xHH works. Keep in sync with front_app.sh.
GLYPH=$(printf '\xEF\x81\x87')

front_app() {
    osascript -e 'tell application "System Events" to get name of first application process whose frontmost is true'
}

case "$1" in
    on)
        : > "$STATE"
        sketchybar --set front_app background.color=$SKY label.color=$BASE \
                                    label="$(front_app) $GLYPH"
        ;;
    off)
        rm -f "$STATE"
        sketchybar --set front_app background.color=$LAVENDER label.color=$BASE \
                                    label="$(front_app)"
        ;;
    *)
        echo "usage: $0 on|off" >&2; exit 1 ;;
esac
