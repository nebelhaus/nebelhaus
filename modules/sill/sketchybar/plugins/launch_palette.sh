#!/bin/bash
# Launch pounce-palette with proper GUI context
# Sketchybar click scripts run in a context that may not allow GUI apps to display
# This wrapper ensures the palette can open properly

# Include nix profile paths so pounce-* commands are available
export PATH="/etc/profiles/per-user/$(id -un)/bin:/run/current-system/sw/bin:$PATH"

# Run in background with nohup to detach from sketchybar's context
nohup pounce-palette >/dev/null 2>&1 &
