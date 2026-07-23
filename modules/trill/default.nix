# trill — the nebelhaus Messages client, installed through Nix (the `trill` flake
# input's overlay puts `pkgs.trill` in scope) instead of a Homebrew cask, so it
# rides the same flake-lock chain as the rest of the family. The flake wraps
# trill's CI-built, Developer-ID-signed, notarized release .app (macOS 26 blocks a
# from-source Nix build — see the trill repo), so `pkgs.trill` is that exact
# bundle in the store.
#
# trill is a normal windowed app, not a daemon like pounce, so there's no launch
# agent — it just needs to exist somewhere Spotlight/Launchpad can find it. But a
# Nix store path is not that place: Full Disk Access (trill reads
# ~/Library/Messages/chat.db, always read-only) is granted per app *path*, and a
# store path changes on every version bump, which would drop the grant. So copy
# the bundle to a FIXED /Applications/Trill.app on activation (the same path the
# old cask used, so an existing grant carries over), re-copying only when the
# store path actually changes. No re-sign dance: the release .app is already
# Developer-ID signed, and an FDA grant keyed to that stable identity + path
# survives rebuilds. `ditto` preserves the signature + notarization staple.
{
  config,
  lib,
  pkgs,
  ...
}:

lib.mkIf config.nebelhaus.trill.enable {
  system.activationScripts.postActivation.text = ''
    # --- trill: install the notarized app at a fixed /Applications path -------
    trillStore="${pkgs.trill}/Applications/Trill.app"
    trillDest="/Applications/Trill.app"
    trillMarker="/Library/Application Support/nebelhaus/trill.installed-from"
    if [ "$(/bin/cat "$trillMarker" 2>/dev/null)" != "${pkgs.trill}" ]; then
      echo "trill: installing ${pkgs.trill} → $trillDest" >&2
      if /usr/bin/ditto "$trillStore" "$trillDest.new"; then
        /bin/rm -rf "$trillDest"
        /bin/mv "$trillDest.new" "$trillDest"
        /bin/mkdir -p "$(/usr/bin/dirname "$trillMarker")"
        /usr/bin/printf '%s' "${pkgs.trill}" > "$trillMarker"
      else
        echo "trill: ditto failed; leaving any existing $trillDest in place" >&2
        /bin/rm -rf "$trillDest.new"
      fi
    fi
  '';
}
