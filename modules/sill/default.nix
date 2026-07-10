# Sill — a windowsill for your menu bar. SketchyBar, launched via nix-darwin,
# with the stray-agent eviction that keeps a rogue `brew services` instance from
# stealing the lock file.
#
# The workspace pills are data-driven: WORKSPACES / LAUNCHER_KEYS / ws_icon are
# generated from nebelhaus.prowl.apps (the shared app roster) so the bar can't
# drift from AeroSpace's launcher. Two personal items (elgato, harvest) are
# gated behind nebelhaus.sill.plugins and off by default.
{
  config,
  lib,
  pkgs,
  username,
  ...
}:

let
  withGUIWait = import ../lib/gui-wait.nix;
  userPath = "/run/current-system/sw/bin:/etc/profiles/per-user/${username}/bin:/opt/homebrew/bin:/opt/homebrew/sbin:/usr/bin:/bin:/usr/sbin:/sbin";

  apps = config.nebelhaus.prowl.apps;

  bashArray = xs: lib.concatMapStringsSep " " (x: ''"${x}"'') xs;
  appWorkspaces = lib.filter (w: w != null) (map (a: a.workspace) apps);
  iconFont =
    icon: if lib.hasPrefix ":" icon then "sketchybar-app-font:Regular:16.0" else "Hack Nerd Font:Bold:17.0";
  wsIconCases = lib.concatMapStrings (
    a:
    lib.optionalString (
      a.workspace != null && a.barIcon != null
    ) "    ${a.workspace}) ICON=${lib.escapeShellArg a.barIcon} ; IFONT=${lib.escapeShellArg (iconFont a.barIcon)} ;;\n"
  ) apps;

  # Sourced by sketchybarrc: the workspace roster + a per-workspace icon lookup.
  # bash 3.2 (macOS /bin/bash) has no associative arrays, hence the case in a fn.
  workspacesSh = ''
    #!/bin/bash
    # GENERATED from nebelhaus.prowl.apps by modules/sill/default.nix — do not edit.
    WORKSPACES=(${bashArray ([ "1" "2" "3" "4" ] ++ appWorkspaces)})
    # Leader picker bubbles: the digits 1-4 (focus a numbered workspace) plus one
    # per app key (jump to its workspace) — mirrors [mode.launch.binding].
    LAUNCHER_KEYS=(${bashArray ([ "1" "2" "3" "4" ] ++ map (a: a.key) apps)})

    # ws_icon <workspace>: sets ICON + IFONT. Default is the workspace's own
    # letter in the bar's Nerd Font; app-workspaces override to their logo glyph.
    ws_icon() {
      ICON="$1"
      IFONT="Hack Nerd Font:Bold:17.0"
      case "$1" in
    ${wsIconCases}  esac
    }
  '';

  # The two gated personal items, emitted only when nebelhaus.sill.plugins lists
  # them. They reference $SURFACE0 (from colors.sh) and $HOME, both live when
  # sketchybarrc sources this file.
  optionalPluginBlocks = {
    # Agent-pane status. The refresh is push, not poll: agents-hook.sh invokes
    # agents.sh directly on every Claude state change, so the pill updates even
    # while hidden (a drawing=off item's own update_freq never ticks, and custom
    # --trigger events are delivered inconsistently across --reload — neither can
    # revive a hidden pill). update_freq is only a while-visible backstop to reap
    # stale files. Starts hidden; agents.sh flips it on when a pane is live.
    # Popup styling mirrors the apple-logo menu.
    agents = ''
      sketchybar --add item agents right \
          --set agents \
              update_freq=10 \
              drawing=off \
              icon.padding_left=10 \
              icon.padding_right=4 \
              label.padding_right=10 \
              label.font="Hack Nerd Font:Bold:14.0" \
              popup.background.border_width=2 \
              popup.background.corner_radius=10 \
              popup.background.border_color=$SURFACE0 \
              popup.background.color=$MANTLE \
              popup.horizontal=off \
              script="$HOME/.config/sketchybar/plugins/agents.sh" \
              click_script="$HOME/.config/sketchybar/plugins/agents.sh" \
          --subscribe agents mouse.clicked system_woke
    '';
    elgato = ''
      sketchybar --add item elgato right \
          --set elgato \
              update_freq=5 \
              script="$HOME/.config/sketchybar/plugins/elgato.sh" \
              background.color=$SURFACE0 \
              icon.padding_left=10 \
              icon.padding_right=10 \
              click_script="$HOME/.config/sketchybar/plugins/elgato.sh" \
          --subscribe elgato mouse.clicked
    '';
    harvest = ''
      sketchybar --add item harvest right \
          --set harvest \
              update_freq=3 \
              script="$HOME/.config/sketchybar/plugins/harvest.sh" \
          --subscribe harvest mouse.clicked harvest_update system_woke
    '';
  };
  optionalItemsSh =
    ''
      #!/bin/bash
      # GENERATED from nebelhaus.sill.plugins by modules/sill/default.nix — do not edit.
    ''
    + lib.concatMapStrings (name: optionalPluginBlocks.${name}) config.nebelhaus.sill.plugins;
in
lib.mkIf config.nebelhaus.sill.enable {
  # SketchyBar (brew) + its tap. sketchybar-app-font renders the workspace pill
  # glyphs (an icon ligature font: `:ghostty:` → that app's logo).
  homebrew.taps = [ "FelixKratz/formulae" ];
  homebrew.brews = [ "FelixKratz/formulae/sketchybar" ];
  fonts.packages = [ pkgs.sketchybar-app-font ];

  launchd.user.agents.sketchybar = {
    serviceConfig = {
      ProgramArguments = withGUIWait "/opt/homebrew/opt/sketchybar/bin/sketchybar";
      KeepAlive = true;
      RunAtLoad = true;
      ProcessType = "Interactive";
      StandardOutPath = "/tmp/sketchybar.out.log";
      StandardErrorPath = "/tmp/sketchybar.err.log";
      EnvironmentVariables = {
        LANG = "en_US.UTF-8";
        PATH = userPath;
      };
    };
  };

  # SketchyBar is launched solely by the agent above — never by `brew services`.
  # If a stray `brew services` plist is left behind, that second instance grabs
  # the lock file and our agent silently fails to draw (symptom: empty menu bar,
  # "could not acquire lock-file … already running?" in the err log). Boot it out
  # and delete its plist on every rebuild. Idempotent no-op when clean.
  system.activationScripts.postActivation.text = ''
    uid=$(/usr/bin/id -u ${username})
    strayPlist="/Users/${username}/Library/LaunchAgents/homebrew.mxcl.sketchybar.plist"
    if [ -e "$strayPlist" ]; then
      echo "[activation] evicting stray homebrew.mxcl.sketchybar agent" >&2
      /bin/launchctl bootout "gui/$uid/homebrew.mxcl.sketchybar" 2>/dev/null || true
      rm -f "$strayPlist"
    fi
  '';

  home-manager.users.${username} =
    {
      lib,
      nebelung,
      ...
    }:
    let
      # The Nebelung palette (name -> "#rrggbb") rendered as sketchybar's
      # 0xAARRGGBB colour literals, fully opaque. Generated so the palette stays
      # single-sourced from the nebelung input — sketchybarrc and every plugin
      # `source` this instead of hardcoding Catppuccin hexes. Var names are the
      # UPPER-cased palette keys (BASE, SURFACE0, MAUVE, …).
      colorsSh = ''
        #!/bin/bash
        # GENERATED from the `nebelung` flake input (nebelung.palette). Do not edit
        # by hand — change colours in ~/code/nebelhaus/nebelung and rebuild.
        ${lib.concatStringsSep "\n" (
          lib.mapAttrsToList (
            name: hex: "export ${lib.toUpper name}=0xff${lib.removePrefix "#" hex}"
          ) nebelung.palette
        )}
      '';
    in
    {
      home.file = {
        ".config/sketchybar/colors.sh".text = colorsSh;
        ".config/sketchybar/workspaces.sh".text = workspacesSh;
        ".config/sketchybar/optional_items.sh".text = optionalItemsSh;
        ".config/sketchybar/sketchybarrc".source = ./sketchybar/sketchybarrc;
        # The far-left logo pill's image: the nebelhaus ears (the two cat-ear
        # shapes of the org mark, extracted from web/logos/nebelhaus-mark and
        # tinted PINK). Drawn as apple.logo's background.image in sketchybarrc.
        ".config/sketchybar/nebelhaus-ears.png".source = ./sketchybar/nebelhaus-ears.png;
        ".config/sketchybar/aerospace-notify.sh".source = ./sketchybar/aerospace-notify.sh;
        ".config/sketchybar/plugins".source = ./sketchybar/plugins;
      };
    };
}
