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

  # The built-in command set exposed by the pounce-commands package. The daemon
  # discovers commands from these dirs itself (in-process launcher, see below),
  # so it needs the same values the pounce-palette wrapper bakes in.
  builtinCommandsDir = "${pkgs.pounce-commands}/share/pounce/commands";

  # Launch-mode cheatsheet rows — generated from the app roster so the "Caps
  # Lock" page always matches AeroSpace's launcher, then the fixed leader
  # actions (resize / clipboard / emoji / exit) appended.
  launchModeItems =
    (map (a: {
      key = a.key;
      action = if a.label != null then a.label else a.name;
    }) config.nebelhaus.prowl.apps)
    ++ [
      {
        key = "1-4";
        action = "Focus workspace 1-4";
      }
      {
        key = "- / =";
        action = "Resize active tile (repeats)";
      }
      {
        key = "v / e";
        action = "Clipboard / Emoji";
      }
      {
        key = "/";
        action = "This cheatsheet";
      }
      {
        key = "⎋";
        action = "Exit launch mode";
      }
    ];

  # The tiling / workspace / service / system pages, rendered from the SAME table
  # that generates the aerospace.toml bindings (../prowl/wm-bindings.nix) — edit a
  # binding there and its cheatsheet row moves with it, so they can't drift. Only
  # items with a `keys` display appear (toml-only bindings are skipped).
  wmPages = map (section: {
    title = section.title;
    items = map (it: {
      key = it.keys;
      action = it.action;
    }) (lib.filter (it: it ? keys) section.items);
  }) (import ../prowl/wm-bindings.nix);

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
lib.mkIf config.nebelhaus.pounce.enable {
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
        # The daemon owns ⌘Space in-process and builds the launcher itself, so it
        # discovers commands from its OWN environment — the same dirs pounce-palette
        # uses. Built-ins + this rice's commands; ~/.config/pounce/commands is
        # always searched last by the daemon. (AeroSpace no longer spawns
        # pounce-palette on ⌘Space — see modules/prowl/aerospace.toml.)
        POUNCE_BUILTIN_DIR = builtinCommandsDir;
        POUNCE_EXTRA_COMMAND_DIRS = "${riceCommands}";
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
      # ⌘Space, registered in-process by the daemon for a near-instant open (no
      # shell/client spawn). Set enabled = false to hand ⌘Space back to an
      # external binder (see modules/prowl/aerospace.toml).
      hotkey = {
        enabled = true;
        key = "space";
        modifiers = [ "cmd" ];
      };
      clipboard = {
        enabled = true;
        maxEntries = 200;
        blacklistBundleIds = [ "com.apple.Passwords" ];
        autoPaste = true; # synthesize ⌘V into the prior app; needs Accessibility
      };
    };

    home.file.".config/pounce/cheatsheet.json".text = builtins.toJSON ([
      {
        title = "Launch Mode [Caps Lock]";
        items = launchModeItems;
      }
    ]
    ++ wmPages
    ++ [
      # ── Tips page (⇥ flips to it) — workflows and the stuff that's hard to
      # remember. Keep every entry TRUE to the configs it describes: keys from
      # hearth/zellij/config.kdl + prowl/aerospace.toml, palette queries from
      # the `# pounce: name` headers in ./commands.
      {
        title = "Terminal · Zellij";
        page = "Tips";
        items = [
          { key = "⌃ ⇥"; action = "Cycle tabs, in any mode"; }
          { key = "⌥ Click path"; action = "Open a repo-named tab cwd'd there"; }
          { key = "Click image"; action = "Near-fullscreen chafa preview"; }
          { key = "⌘ p / ⌘ t"; action = "New pane (same cwd) / new tab (~)"; }
          { key = "⌘ ⇧ t"; action = "New tab via folder picker"; }
          { key = "⌘ y / ⌘ ⇧ y"; action = "Yazi: peek files / jump to a shell"; }
        ];
      }
      {
        title = "Claude Agents";
        page = "Tips";
        items = [
          { key = "⌃ ⌥ c"; action = "Agent in an isolated worktree branch"; }
          { key = "⌃ ⌥ ⇧ c"; action = "Agent in this checkout (one per tab)"; }
          { key = "haus status"; action = "Agent branches, dirty repos, stale locks"; }
          { key = "haus try"; action = "Build against local checkouts (no push)"; }
          { key = "haus ship"; action = "Push the chain, bumping locks per hop"; }
        ];
      }
      {
        title = "Workflows";
        page = "Tips";
        items = [
          { key = "⇪ v ↵"; action = "Pastes straight into the app you left"; }
          { key = "⌥ ⇧ x → ⇪ x"; action = "Throw window to app's workspace, follow it"; }
          { key = "⇪ - - -"; action = "Resize repeats without re-tapping caps (⎋ ends)"; }
          { key = "⌥ ⇧ r"; action = "Untangle windows after a laptop wake"; }
        ];
      }
      {
        title = "Palette Recipes [⌘ Space]";
        page = "Tips";
        items = [
          { key = "rebuild"; action = "Rebuild + switch this Mac"; }
          { key = "nix"; action = "Open the nix config in your editor"; }
          { key = "reload"; action = "Reload SketchyBar / AeroSpace"; }
          { key = "force"; action = "Force-quit an app"; }
        ];
      }
    ]);

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
