#!/bin/bash
# peek.sh — Super y: summon the floating yazi "peek" panel, rooted at the
# focused pane's cwd.
#
# Why a separate Ghostty instance instead of a zellij floating pane: zellij's
# VTE parser strips kitty-graphics APC sequences, so yazi inside zellij can
# only render chafa block art. Against raw Ghostty, yazi gets the real kitty
# graphics protocol — crisp side-pane previews — and image-preview.sh (the
# Enter opener for images) upgrades itself to full-res kitty rendering too.
# (Ghostty already speaks kitty graphics, so there's nothing to gain from
# dragging a heavier terminal like kitty into the rice just for this.)
#
# Spawn model: this fires ONE fresh, centered Ghostty instance per summon via
# the shared float-term helper — the same "spawn → PID-diff → AppleScript
# settle → aerospace-float" dance the Rebuild System pounce command uses. yazi
# runs inside it; when yazi quits (q/Esc), peek-run.sh exits, and Ghostty
# closes the window (wait-after-command defaults off). No background window,
# no fifo, no offscreen parking — the panel exists only while it's on screen.
#
# Trade-off vs the old persistent-window design: each summon pays a cold spawn
# (a new Ghostty instance launch) instead of teleporting a parked one, so the
# panel appears a touch slower and may briefly flash at its saved frame before
# the AppleScript settle re-centers it — identical to how Rebuild System pops
# in. In exchange there's no lingering hidden instance to babysit.

set -u
export PATH="/opt/homebrew/bin:/etc/profiles/per-user/$USER/bin:/run/current-system/sw/bin:$PATH"

FLOAT_TERM="$HOME/.config/zellij/float-term.sh"
WINDOW_TITLE="quick-terminal-peek"

# Root peek at the REAL repo, not a throwaway worktree checkout: if the
# summoning pane sits inside a linked git worktree (its per-worktree gitdir
# differs from the shared common dir), start yazi at the repo's MAIN worktree —
# the first entry of `git worktree list` — so peek always opens you in the
# canonical repo. A normal checkout (gitdir == common dir) or a non-repo cwd
# falls through to $PWD unchanged.
START="$PWD"
_gd="$(git -C "$PWD" rev-parse --path-format=absolute --git-dir 2>/dev/null)"
_gcd="$(git -C "$PWD" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)"
if [ -n "$_gd" ] && [ "$_gd" != "$_gcd" ]; then
    _main="$(git -C "$PWD" worktree list --porcelain 2>/dev/null | sed -n '1s/^worktree //p')"
    [ -n "$_main" ] && [ -d "$_main" ] && START="$_main"
fi

# Spawn a centered Ghostty running peek-run.sh. Bigger than Rebuild System's
# 750×400 popup (peek is a file browser with image previews) — 80% of the
# cursor's screen. --pin lands it on the current workspace and force-floats it.
# cwd rides in on --working-directory (an EXTRA ghostty flag after `--`); the
# summoning zellij session leaks through `open`'s env-forward, which peek-run.sh
# captures for its Enter-opens-a-tab handoff before scrubbing $ZELLIJ.
"$FLOAT_TERM" spawn \
    --title "$WINDOW_TITLE" \
    --pct 80 \
    --pin \
    --command "/bin/bash $HOME/.config/zellij/peek-run.sh" \
    -- --working-directory="$START" >/dev/null
