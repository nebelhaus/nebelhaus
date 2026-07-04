#!/bin/bash
# Super-Shift-t "New tab" flow: launched as a zellij floating pane. Browse in yazi
# (starts at $HOME — or at a shortlist of it, see below; l/Right to enter dirs,
# h/Left up), then Enter on the folder
# you want spawns a new zellij tab cwd'd there and auto-named after the repo
# (git-root basename, or the dir basename if it isn't a repo). Press q or Esc to
# cancel — the pane just closes and no tab is created.
#
# The Enter=pick / q=cancel behaviour comes from the dedicated picker keymap in
# ~/.config/yazi-picker (see dotfiles/yazi/picker/): Enter runs `enter` + `quit`
# so yazi writes the chosen dir to --cwd-file, while q/Esc run `quit
# --no-cwd-file` so nothing is written and the tab-spawn block below is skipped.
set -u
export PATH="/etc/profiles/per-user/$USER/bin:/run/current-system/sw/bin:$PATH"
export YAZI_CONFIG_HOME="$HOME/.config/yazi-picker"

# Where the picker starts: $HOME by default, but if the host set
# nebelhaus.hearth.newTabDirs, hearth writes ~/.config/zellij/newtab-dirs
# (one home-relative dir per line) and we rebuild a throwaway "home" of
# symlinks to just those dirs — so the picker opens on a shortlist instead of
# every file in $HOME. Inside them navigation is normal yazi; the picked path
# is resolved back through the symlink below. This shortlist only exists for
# this picker — regular yazi sessions are untouched.
start="$HOME"
dirs_file="$HOME/.config/zellij/newtab-dirs"
if [ -s "$dirs_file" ]; then
    farm="${TMPDIR:-/tmp}/zellij-newtab-picker-$USER/home"
    rm -rf "$farm" && mkdir -p "$farm"
    while IFS= read -r d; do
        [ -n "$d" ] && [ -d "$HOME/$d" ] || continue
        # Nested entries ("code/work") get their parent dirs materialised so
        # the shortlist shows the same shape as the real home.
        case "$d" in */*) mkdir -p "$farm/${d%/*}" ;; esac
        ln -sfn "$HOME/$d" "$farm/$d"
    done < "$dirs_file"
    # If nothing on the list exists (fresh machine, renamed dirs), fall back
    # to browsing $HOME rather than showing an empty picker.
    [ -n "$(ls -A "$farm")" ] && start="$farm"
fi

tmp="$(mktemp -t yazi-cwd.XXXXXX)"
yazi --cwd-file="$tmp" "$start"
cwd="$(cat -- "$tmp" 2>/dev/null)"
rm -f -- "$tmp"

if [ -n "$cwd" ] && [ -d "$cwd" ]; then
    # Resolve through the shortlist's symlinks so the tab cwd (and the name
    # derived from it) is the real directory, not the picker's throwaway copy.
    cwd="$(cd "$cwd" && pwd -P)"
    name="$(basename "$cwd")"
    root="$(git -C "$cwd" rev-parse --show-toplevel 2>/dev/null)"
    [ -n "$root" ] && name="$(basename "$root")"

    # zellij's `new-tab --cwd` is silently ignored when a custom default_layout
    # with a default_tab_template is active (v0.44) — the tab spawns in $HOME
    # regardless. Work around it by cloning the active layout and injecting a
    # `cwd` onto its content tab (tab-level cwd IS honored; root-level is not),
    # then opening the tab from that layout. Reusing custom.kdl verbatim keeps
    # the tab-bar/status-bar and the spiral/columns/grid swap layouts intact.
    layout_src="$HOME/.config/zellij/layouts/custom.kdl"
    gen=""
    if [ -f "$layout_src" ]; then
        # KDL-escape the path (backslash then double-quote) for the cwd string.
        esc="${cwd//\\/\\\\}"; esc="${esc//\"/\\\"}"
        # Reused, overwritten each run — no per-invocation temp file to race the
        # zellij server on cleanup, and it never accumulates.
        gen="${TMPDIR:-/tmp}/zellij-newtab-$USER.kdl"
        awk -v cwd="$esc" '
            /^    tab \{$/ && !done { print "    tab cwd=\"" cwd "\" {"; done=1; next }
            { print }
        ' "$layout_src" > "$gen"
        grep -q '^    tab cwd=' "$gen" || gen=""
    fi

    if [ -n "$gen" ]; then
        zellij action new-tab --layout "$gen" --name "$name"
    else
        # Fallback (layout missing/reformatted): at least name the tab; cwd may
        # land in $HOME until the layout can be cloned again.
        zellij action new-tab --cwd "$cwd" --name "$name"
    fi
fi

# Selection made or cancelled — either way close this floating picker pane.
exit 0
