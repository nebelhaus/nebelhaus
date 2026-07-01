# withGUIWait: wrap a GUI agent's launch so it survives cold boot.
#
# Two problems this solves, both from launching GUI agents via launchd on
# Determinate Nix:
#   1. The launcher must NOT live in /nix/store. Determinate mounts /nix from a
#      separate APFS volume; at cold boot the user-domain launchd evaluates
#      plists before that volume is reliably up, the kernel reports "Missing
#      executable", and the job parks with last exit = 78 (EX_CONFIG). Embedding
#      the script inline keeps it on the boot volume (~/Library/LaunchAgents).
#   2. We wait until the GUI (Aqua) session is actually ready before exec'ing —
#      the Aqua-session limit alone isn't enough (e.g. AeroSpace's Carbon hotkey
#      registration silently no-ops if the event manager isn't up yet).
#
# Usage:  ProgramArguments = withGUIWait "/Applications/AeroSpace.app/Contents/MacOS/AeroSpace";
target: [
  "/bin/bash"
  "-c"
  ''
    until /usr/bin/pgrep -x Dock >/dev/null 2>&1; do sleep 1; done
    until /usr/bin/pgrep -x Finder >/dev/null 2>&1; do sleep 1; done
    until /usr/bin/pgrep -x SystemUIServer >/dev/null 2>&1; do sleep 1; done
    deadline=$(( $(date +%s) + 60 ))
    until /usr/bin/osascript -e 'tell application "System Events" to count processes' >/dev/null 2>&1; do
      [ "$(date +%s)" -gt "$deadline" ] && break
      sleep 1
    done
    sleep 5
    exec "$0"
  ''
  target
]
