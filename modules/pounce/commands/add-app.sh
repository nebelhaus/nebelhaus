#!/bin/bash
# pounce: name = Install App
# pounce: description = Search Homebrew — install, or add to your tiling roster
# pounce: icon = square.and.arrow.down.on.square
# pounce: submenu = true
#
# Declarative app installer. Fuzzy-search Homebrew's offline catalog (casks +
# formulae); on Enter, a short menu decides the app's fate:
#
#   • Add to roster  — a GUI app (cask) gets a workspace + Caps-Lock leader key.
#                       Appends an entry to $NEBELHAUS_FLAKE/roster.json.
#   • Just install   — anything: appended to installs.json (casks[] / brews[]).
#
# It NEVER installs imperatively or hand-edits your Nix. It appends a structured
# entry to a JSON file the flake reads (nebelhaus.prowl.rosterFile /
# nebelhaus.homebrew.installsFile), then runs `haus rebuild` in a floating
# terminal — and rolls the append back if the build fails. The catalog is
# Homebrew's own API cache (~/Library/Caches/Homebrew/api/*.jws.json); the flat
# index is rebuilt from it in the background when stale, so no keystroke waits on
# I/O and no live network call is ever made.
#
# Host-agnostic: the flake lives at ~/.config/nix by convention (override with
# $NEBELHAUS_FLAKE), and the rebuild reuses `haus rebuild`, which resolves this
# machine's host attr + does the passwordless switch itself.

# A launchd GUI agent's PATH is bare; resolve our tools (jq, brew, git,
# osascript, pounce) explicitly — same set prowl bakes into AeroSpace.
export PATH="/run/current-system/sw/bin:/etc/profiles/per-user/$USER/bin:/opt/homebrew/bin:/opt/homebrew/sbin:/usr/bin:/bin:/usr/sbin:/sbin"

FLAKE_DIR="${NEBELHAUS_FLAKE:-$HOME/.config/nix}"
ROSTER_JSON="$FLAKE_DIR/roster.json"
INSTALLS_JSON="$FLAKE_DIR/installs.json"
CHEATSHEET="$HOME/.config/pounce/cheatsheet.json"
INDEX="$HOME/.cache/nebelhaus/pkg-index.tsv"
BREW_API="$HOME/Library/Caches/Homebrew/api"
FLOAT_TERM="$HOME/.config/zellij/float-term.sh"

field() { printf '%s' "$1" | cut -f"$2"; }

# ── catalog index ─────────────────────────────────────────────────────────
# One TSV line per package: type \t token \t appname(open -a target) \t desc.
# Casks pull the app's real .app name from the cask's `app` artifact so the
# roster's `name` (and appId lookup) match what macOS actually installs.
build_index() {
  local tmp
  tmp="$(mktemp)" || return 1
  {
    jq -r '.payload | fromjson | .[] | try ([ "cask", .token,
        ((([.artifacts[]?.app? // empty] | flatten | .[0]) // .name[0] // .token) | sub("\\.app$"; "")),
        (.desc // "") ] | @tsv) catch empty' "$BREW_API/cask.jws.json" 2>/dev/null
    jq -r '.payload | fromjson | .[] | try ([ "formula", .name, "", (.desc // "") ] | @tsv) catch empty' \
      "$BREW_API/formula.jws.json" 2>/dev/null
  } >"$tmp"
  if [ -s "$tmp" ]; then
    mv "$tmp" "$INDEX"
  else
    rm -f "$tmp"
    return 1
  fi
}

mkdir -p "$(dirname "$INDEX")"
if [ ! -s "$INDEX" ]; then
  build_index # first run: synchronous (one-time)
elif [ -n "$(find "$INDEX" -mtime +7 2>/dev/null)" ]; then
  (build_index >/dev/null 2>&1 &) # stale: refresh in background, use current now
fi

if [ ! -s "$INDEX" ]; then
  printf 'Run: brew update\tHomebrew catalog cache is empty — populate it, then retry\texclamationmark.triangle\n' \
    | pounce -p "Install App" -i "square.and.arrow.down.on.square" >/dev/null
  exit 0
fi

# ── step 1: search the catalog ────────────────────────────────────────────
# Row: title(token) \t subtitle(desc) \t icon \t actions \t group \t type \t appname
# Fields 6-7 are hidden and echoed back on selection.
list="$(awk -F'\t' '{
  icon  = ($1 == "cask") ? "app.badge" : "terminal"
  group = ($1 == "cask") ? "Apps · cask" : "CLI · formula"
  printf "%s\t%s\t%s\t\t%s\t%s\t%s\n", $2, $4, icon, group, $1, $3
}' "$INDEX")"

selected="$(printf '%s\n' "$list" | pounce -p "Install App — search Homebrew" -i "square.and.arrow.down.on.square")"
[ -z "$selected" ] && exit 0

token="$(field "$selected" 2)"
type="$(field "$selected" 6)"
appname="$(field "$selected" 7)"
[ -z "$token" ] && exit 0
[ -z "$appname" ] && appname="$token"

# ── step 2: choose the lane ───────────────────────────────────────────────
if [ "$type" = "cask" ]; then
  lane_menu="$(printf '%s\t%s\t%s\n%s\t%s\t%s' \
    "Add to roster" "Install $appname + its own workspace and Caps-Lock leader key" "rectangle.3.group" \
    "Just install" "Install $appname only — no tiling, no hotkey" "square.and.arrow.down")"
  lane_sel="$(printf '%s\n' "$lane_menu" | pounce -p "$appname" -i "app.badge")"
  [ -z "$lane_sel" ] && exit 0
  lane="$(field "$lane_sel" 2)"
else
  lane="Just install"
fi

key=""
workspace=""

if [ "$lane" = "Add to roster" ]; then
  # ── step 3: pick a free leader letter ───────────────────────────────────
  # Taken letters = the live cheatsheet's Launch Mode page (the built roster,
  # host list included) plus anything already queued in roster.json.
  used="$(
    jq -r '.[] | select(.title | test("Launch Mode")) | .items[].key' "$CHEATSHEET" 2>/dev/null
    jq -r '.[].key' "$ROSTER_JSON" 2>/dev/null
  )"
  key_list=""
  for L in a b c d e f g h i j k l m n o p q r s t u v w x y z; do
    printf '%s\n' "$used" | grep -qx "$L" && continue
    key_list="$key_list$L	Caps Lock then $L  →  launch $appname	keyboard
"
  done
  if [ -z "$key_list" ]; then
    printf 'No free leader letters left\tEvery a-z leader key is taken — free one first\texclamationmark.triangle\n' \
      | pounce -p "Install App" -i "keyboard" >/dev/null
    exit 0
  fi
  key_sel="$(printf '%s' "$key_list" | pounce -p "Leader key for $appname (Caps Lock + …)" -i "keyboard")"
  [ -z "$key_sel" ] && exit 0
  key="$(field "$key_sel" 2)"

  # ── step 4: workspace or launcher-only ──────────────────────────────────
  ws_menu="$(printf '%s\t%s\t%s\n%s\t%s\t%s' \
    "Own workspace" "Auto-move $appname to its own AeroSpace workspace + bar pill (⌥⇧$key throws to it)" "rectangle.split.3x1" \
    "Launcher-only" "Just the leader key — opens in the current workspace, no pill" "arrow.up.forward.app")"
  ws_sel="$(printf '%s\n' "$ws_menu" | pounce -p "$appname — workspace?" -i "rectangle.3.group")"
  [ -z "$ws_sel" ] && exit 0
  if [ "$(field "$ws_sel" 2)" = "Own workspace" ]; then
    # Workspace name = the leader letter, uppercased — the roster's convention
    # (t→T, b→B). Unique because leader keys are unique.
    workspace="$(printf '%s' "$key" | tr '[:lower:]' '[:upper:]')"
  fi
fi

# ── stage the declarative edit (append + backup for rollback) ─────────────
if [ "$lane" = "Add to roster" ]; then
  [ -s "$ROSTER_JSON" ] || echo '[]' >"$ROSTER_JSON"
  entry="$(jq -n --arg key "$key" --arg name "$appname" --arg cask "$token" --arg label "$appname" --arg ws "$workspace" \
    '{ key: $key, name: $name, cask: $cask, label: $label }
     + (if $ws == "" then {} else { workspace: $ws } end)')"
  cp "$ROSTER_JSON" "$ROSTER_JSON.bak"
  jq --argjson e "$entry" '. + [$e]' "$ROSTER_JSON.bak" >"$ROSTER_JSON" || { mv "$ROSTER_JSON.bak" "$ROSTER_JSON"; exit 1; }
else
  [ -s "$INSTALLS_JSON" ] || echo '{"casks":[],"brews":[]}' >"$INSTALLS_JSON"
  cp "$INSTALLS_JSON" "$INSTALLS_JSON.bak"
  if [ "$type" = "cask" ]; then
    jq --arg t "$token" '.casks = ((.casks // []) + [$t] | unique)' "$INSTALLS_JSON.bak" >"$INSTALLS_JSON" \
      || { mv "$INSTALLS_JSON.bak" "$INSTALLS_JSON"; exit 1; }
  else
    jq --arg t "$token" '.brews = ((.brews // []) + [$t] | unique)' "$INSTALLS_JSON.bak" >"$INSTALLS_JSON" \
      || { mv "$INSTALLS_JSON.bak" "$INSTALLS_JSON"; exit 1; }
  fi
fi

# ── rebuild in a floating terminal, with rollback on failure ──────────────
# Reuses the shared float-term helper (same as rebuild.sh). Baked values are
# quoted with %q; the logic body is a literal (single-quoted) heredoc.
REBUILD_TMP="/tmp/nebelhaus-install-run.sh"
{
  printf 'FLAKE_DIR=%q\n' "$FLAKE_DIR"
  printf 'ROSTER_JSON=%q\n' "$ROSTER_JSON"
  printf 'INSTALLS_JSON=%q\n' "$INSTALLS_JSON"
  printf 'LANE=%q\n' "$lane"
  printf 'KEY=%q\n' "$key"
  printf 'APPNAME=%q\n' "$appname"
  printf 'WORKSPACE=%q\n' "$workspace"
  printf 'TOKEN=%q\n' "$token"
  cat <<'EOF'
export PATH="/run/current-system/sw/bin:/nix/var/nix/profiles/default/bin:/etc/profiles/per-user/$USER/bin:/opt/homebrew/bin:$PATH"
cd "$FLAKE_DIR" || exit 1

# Flakes only read git-tracked files — stage the data files before building.
git add roster.json installs.json 2>/dev/null || true

echo "Installing $APPNAME — building & switching (haus rebuild)…"
echo
if haus rebuild; then
  # For a roster app with a workspace, the on-window-detected auto-herd rule
  # needs the bundle id, which only exists once the cask is installed. Resolve
  # it now and, if we didn't have it, patch the entry and rebuild once more so
  # the app's windows land on their workspace automatically.
  if [ "$LANE" = "Add to roster" ] && [ -n "$WORKSPACE" ]; then
    appid="$(osascript -e "id of app \"$APPNAME\"" 2>/dev/null)"
    have="$(jq -r --arg k "$KEY" '.[] | select(.key == $k) | .appId // ""' "$ROSTER_JSON" 2>/dev/null)"
    if [ -n "$appid" ] && [ -z "$have" ]; then
      jq --arg k "$KEY" --arg id "$appid" '(.[] | select(.key == $k) | .appId) |= $id' "$ROSTER_JSON" >"$ROSTER_JSON.tmp" \
        && mv "$ROSTER_JSON.tmp" "$ROSTER_JSON" && git add roster.json 2>/dev/null
      echo
      echo "Resolved bundle id ($appid) — one more rebuild so windows auto-herd…"
      echo
      haus rebuild || true
    fi
  fi
  echo
  echo "✓ $APPNAME is installed and wired."
  rm -f "$ROSTER_JSON.bak" "$INSTALLS_JSON.bak"
else
  echo
  echo "✗ Rebuild failed — rolling back the change (nothing was added)."
  [ -f "$ROSTER_JSON.bak" ] && mv "$ROSTER_JSON.bak" "$ROSTER_JSON"
  [ -f "$INSTALLS_JSON.bak" ] && mv "$INSTALLS_JSON.bak" "$INSTALLS_JSON"
  git add roster.json installs.json 2>/dev/null || true
fi
echo
echo "Press any key to close…"
read -n 1 -s
EOF
} >"$REBUILD_TMP"

xattr -d com.apple.quarantine "$REBUILD_TMP" 2>/dev/null || true

"$FLOAT_TERM" spawn \
  --title "quick-terminal-install" \
  --w 800 --h 480 --cols 84 --rows 24 \
  --pin \
  --command "bash $REBUILD_TMP" >/dev/null
