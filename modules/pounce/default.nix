# Pounce — the launcher, wired into the system. Runs the pounce daemon as a
# launch agent and frees ⌘Space for it.
#
# The daemon needs a STABLE code-signing identity so a macOS Accessibility (TCC)
# grant survives rebuilds — a store path's adhoc cdhash changes every build,
# losing any grant keyed to it. The nix sandbox can't reach the login keychain,
# so when you provide `nebelhaus.pounce.signingIdentity` we sign impurely here in
# the Aqua session: copy Pounce.app to a fixed writable path, codesign it with
# your Apple Development identity (stable designated requirement → grant
# persists), and exec the daemon from that copy. A marker records which store
# path the copy was signed from, so we only re-sign when pounce actually changed.
{
  config,
  lib,
  pkgs,
  username,
  ...
}:

let
  identity = config.nebelhaus.pounce.signingIdentity;

  # Wait for the GUI session (→ the /nix volume + an unlocked login keychain)
  # before touching the store path or codesign. Exec'ing via /bin/bash (boot
  # volume) also sidesteps the cold-boot exit-78 race for store-path executables.
  guiWait = ''
    until /usr/bin/pgrep -x Dock >/dev/null 2>&1; do sleep 1; done
    until /usr/bin/pgrep -x Finder >/dev/null 2>&1; do sleep 1; done
    until /usr/bin/pgrep -x SystemUIServer >/dev/null 2>&1; do sleep 1; done
  '';

  # Unsigned: just run the daemon from the store. Signed: copy + re-sign first.
  daemonScript =
    if identity == "" then
      ''
        ${guiWait}
        exec "${pkgs.pounce}/Applications/Pounce.app/Contents/MacOS/pounce" --daemon
      ''
    else
      ''
        ${guiWait}
        STORE_APP="${pkgs.pounce}/Applications/Pounce.app"
        STATE_DIR="$HOME/.local/state/pounce"
        DEST="$STATE_DIR/Pounce.app"
        MARKER="$STATE_DIR/.signed-from"

        if [ ! -d "$DEST" ] || [ "$(/bin/cat "$MARKER" 2>/dev/null)" != "$STORE_APP" ]; then
          /bin/mkdir -p "$STATE_DIR"
          /bin/rm -rf "$DEST"
          if /bin/cp -R "$STORE_APP" "$DEST" \
             && /bin/chmod -R u+w "$DEST" \
             && /usr/bin/codesign --force --identifier com.local.pounce -s "${identity}" "$DEST"; then
            /usr/bin/printf '%s' "$STORE_APP" > "$MARKER"
          else
            echo "pounce: codesign failed, falling back to unsigned store binary (no Accessibility)" >&2
            /bin/rm -f "$MARKER"
            exec "$STORE_APP/Contents/MacOS/pounce" --daemon
          fi
        fi
        exec "$DEST/Contents/MacOS/pounce" --daemon
      '';
in
{
  launchd.user.agents.pounce = {
    serviceConfig = {
      ProgramArguments = [
        "/bin/bash"
        "-c"
        daemonScript
      ];
      KeepAlive = true;
      RunAtLoad = true;
      ProcessType = "Interactive";
      StandardOutPath = "/tmp/pounce.out.log";
      StandardErrorPath = "/tmp/pounce.err.log";
      EnvironmentVariables = {
        LANG = "en_US.UTF-8";
        HOME = "/Users/${username}";
      };
    };
  };

  # All home-manager wiring in ONE block — a dynamic attr key (${username}) can't
  # be merged across multiple statements. Passed as a module FUNCTION so it gets
  # home-manager's extended `lib` (for lib.hm.dag) and the overlaid `pkgs`.
  home-manager.users.${username} = { lib, pkgs, ... }: {
    home.packages = [
      pkgs.pounce
      # The generic command library, plus this rice's own commands (rebuild,
      # nix-config, reload-bar, reload-aerospace) layered on via runtime
      # discovery — each is a self-describing script in ./commands (metadata in
      # its `# pounce:` header). Same-filename scripts shadow pounce built-ins.
      (pkgs.pounce-commands.override { extraCommandDirs = [ ./commands ]; })
    ];

    # Palette settings — pounce re-reads this on each open. Edit + rebuild.
    home.file.".config/pounce/config.json".text = builtins.toJSON {
      windowMode = "compact"; # "default" | "compact"
      clipboard = {
        enabled = true;
        maxEntries = 200;
        blacklistBundleIds = [ "com.apple.Passwords" ];
        autoPaste = true; # synthesize ⌘V into the prior app; needs Accessibility
      };
    };

    # Free ⌘Space for the palette by disabling Spotlight's "Show Spotlight
    # search" shortcut (symbolic hotkey 64). Integer-typed values are REQUIRED —
    # a string fragment leaves the binding half-alive and it races AeroSpace's
    # Carbon ⌘Space registration. Full effect on next login; activateSettings -u
    # applies what it can now.
    home.activation.disableSpotlightCmdSpace = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      $DRY_RUN_CMD /usr/bin/defaults write com.apple.symbolichotkeys AppleSymbolicHotKeys \
        -dict-add 64 '<dict><key>enabled</key><integer>0</integer><key>value</key><dict><key>type</key><string>standard</string><key>parameters</key><array><integer>32</integer><integer>49</integer><integer>1048576</integer></array></dict></dict>'
      $DRY_RUN_CMD /System/Library/PrivateFrameworks/SystemAdministration.framework/Resources/activateSettings -u || true
    '';
  };
}
