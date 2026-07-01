#!/bin/bash

source "$HOME/.config/sketchybar/colors.sh"

URL="http://elgato-key-light-mini-57a3.local:9123/elgato/lights"

if [ "$SENDER" = "mouse.clicked" ]; then
    # Get current state
    CURRENT_STATE=$(curl -s "$URL" | jq '.lights[0].on')
    
    # Toggle state
    if [ "$CURRENT_STATE" -eq 1 ]; then
        NEW_STATE=0
    else
        NEW_STATE=1
    fi
    
    # Send new state
    curl -s -X PUT -d "{\"lights\":[{\"on\":$NEW_STATE}]}" "$URL" > /dev/null
    
    # Wait a tiny bit for the light to update internally
    sleep 0.1
fi

# Update UI
DATA=$(curl -s "$URL")
STATE=$(echo "$DATA" | jq '.lights[0].on')

if [ "$STATE" -eq 1 ]; then
    sketchybar --set $NAME \
        icon="" \
        icon.color=$BASE \
        background.color=$YELLOW \
        label.drawing=off
else
    sketchybar --set $NAME \
        icon="" \
        icon.color=$TEXT \
        background.color=$SURFACE0 \
        label.drawing=off
fi
