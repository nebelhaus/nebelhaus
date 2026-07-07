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
  hostname,
  ...
}:

let
  identity = config.nebelhaus.pounce.signingIdentity;

  # This rice's palette commands (see ./commands — one self-describing script
  # each, metadata in a `# pounce:` header). rebuild.sh can't guess the flake's
  # host attr name at runtime, so @hostname@ is substituted here at build time
  # from mkNebelhaus's hostname.
  riceCommands = pkgs.runCommand "nebelhaus-pounce-commands" { } ''
    mkdir -p $out
    install -m555 ${./commands}/*.sh $out/
    rm $out/rebuild.sh
    substitute ${./commands/rebuild.sh} $out/rebuild.sh \
      --subst-var-by hostname ${lib.escapeShellArg hostname}
    chmod 555 $out/rebuild.sh
  '';

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
      # The generic command library, plus this rice's own commands layered on
      # via runtime discovery. Same-filename scripts shadow pounce built-ins.
      (pkgs.pounce-commands.override { extraCommandDirs = [ riceCommands ]; })
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

    home.file.".config/pounce/cheatsheet.json".text = builtins.toJSON [
      {
        title = "Launch Mode [Caps Lock]";
        items = [
          { key = "t"; action = "Ghostty (Terminal)"; }
          { key = "s"; action = "Slack"; }
          { key = "b"; action = "Zen (Browser)"; }
          { key = "f"; action = "Figma"; }
          { key = "m"; action = "Music"; }
          { key = "h"; action = "Swather"; }
          { key = "c"; action = "Claude"; }
          { key = "d"; action = "Notion Calendar"; }
          { key = "n"; action = "Obsidian"; }
          { key = "r"; action = "Things3"; }
          { key = "p"; action = "Passwords"; }
          { key = "- / ="; action = "Resize active tile (repeats)"; }
          { key = "v / e"; action = "Clipboard / Emoji"; }
          { key = "/"; action = "This cheatsheet"; }
          { key = "⎋"; action = "Exit launch mode"; }
        ];
      }
      {
        title = "Window Management";
        items = [
          { key = "⌥ hjkl"; action = "Focus direction"; }
          { key = "⌥ ⌘ ⌃ ⇧ ←↓↑→"; action = "Move window"; }
          { key = "⌥ ⌘ ⌃ ⇧ -/="; action = "Resize window"; }
          { key = "⌥ /"; action = "Tiles layout"; }
          { key = "⌥ ,"; action = "Accordion layout"; }
          { key = "⌥ f"; action = "Fullscreen toggle"; }
          { key = "⌥ ⇥"; action = "Back and forth"; }
          { key = "⌥ ⇧ ⇥"; action = "Move workspace to next monitor"; }
        ];
      }
      {
        title = "Workspaces";
        items = [
          { key = "⌥ 1-4"; action = "Focus workspace 1-4"; }
          { key = "⌥ ⇧ 1-4"; action = "Move to workspace 1-4"; }
          { key = "⌥ ⇧ [Letter]"; action = "Move to app workspace"; }
        ];
      }
      {
        title = "Service Mode [⌥ ⇧ ;]";
        items = [
          { key = "r"; action = "Flatten tree"; }
          { key = "f"; action = "Toggle floating"; }
          { key = "⌫"; action = "Close others"; }
          { key = "⌥ ⇧ hjkl"; action = "Join with"; }
          { key = "↑ / ↓"; action = "Volume up / down"; }
          { key = "⇧ ↓"; action = "Mute volume"; }
          { key = "⎋"; action = "Reload config + exit"; }
        ];
      }
      {
        title = "System";
        items = [
          { key = "⌘ Space"; action = "Command Palette"; }
          { key = "⌥ ⇧ r"; action = "Resort windows"; }
        ];
      }
    ];

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

    # A rebuild swaps the store path under the KeepAlive'd daemon, but launchd
    # keeps the OLD image running until something bounces it. The .signed-from
    # marker records which store path the running copy was signed from — when it
    # lags pkgs.pounce, kick the agent; the respawn re-copies + re-signs (the
    # stable identity keeps the Accessibility grant) and clipboard history is
    # on disk, so the bounce loses nothing. Marker match → pounce unchanged →
    # no bounce. Runs in home-manager activation, i.e. after nix-darwin has
    # loaded the new agent plist.
    home.activation.kickstartPounce = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      if [ "$(/bin/cat "$HOME/.local/state/pounce/.signed-from" 2>/dev/null)" != "${pkgs.pounce}/Applications/Pounce.app" ]; then
        $DRY_RUN_CMD /bin/launchctl kickstart -k "gui/$(/usr/bin/id -u)/org.nixos.pounce" || true
      fi
    '';
  };
}
