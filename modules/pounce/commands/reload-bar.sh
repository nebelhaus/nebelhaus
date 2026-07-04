#!/bin/bash
# pounce: name = Reload SketchyBar
# pounce: description = Reload bar configuration
# pounce: icon = arrow.clockwise
# Reload SketchyBar configuration
sketchybar --reload
osascript -e 'display notification "SketchyBar reloaded" with title "SketchyBar"'
