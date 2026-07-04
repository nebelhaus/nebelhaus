#!/bin/bash
# pounce: name = Reload AeroSpace
# pounce: description = Reload AeroSpace configuration
# pounce: icon = rectangle.3.group
# Reload AeroSpace configuration
aerospace reload-config
osascript -e 'display notification "AeroSpace config reloaded" with title "AeroSpace"'
