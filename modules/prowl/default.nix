# Prowl — stake out your screen. AeroSpace tiling, launched via nix-darwin
# (not Login Items) so it survives cold boot, plus the Caps→F18 leader remap and
# a wake-time window re-sort.
#
# The launcher (which app lives on which workspace, its leader key + window
# rules) is data-driven: nebelhaus.prowl.apps is the single source of truth, and
# this module renders it into aerospace.toml (+ the wake-time resort script).
# SketchyBar and the pounce cheatsheet read the same option so nothing drifts.
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

  # Absolute paths baked into the generated configs. AeroSpace's exec-and-forget
  # doesn't shell-expand $HOME, so the home path must be a literal — hence the
  # generation (a plain source file couldn't be user-agnostic).
  homeDir = "/Users/${username}";
  binDir = "/etc/profiles/per-user/${username}/bin";
  launchSh = "${homeDir}/.config/aerospace/launch.sh";

  # Extra roster entries appended by the pounce "Install App" command live in a
  # JSON file (nebelhaus.prowl.rosterFile) so the roster stays machine-editable
  # without hand-patching Nix. Read at build time and folded into the option
  # BELOW (config block) so every consumer — this module, sill's pills, the
  # pounce cheatsheet — sees the merged roster and nothing drifts.
  rosterFile = config.nebelhaus.prowl.rosterFile;
  fileApps = lib.optionals (rosterFile != null) (builtins.fromJSON (builtins.readFile rosterFile));

  apps = config.nebelhaus.prowl.apps;

  # The static tiling/workspace/service bindings, shared with the pounce
  # cheatsheet (see ./wm-bindings.nix — one table, rendered both ways so they
  # can't drift). Render each item's `binds` into aerospace.toml lines; a chord
  # maps to a single command ('cmd') or a list of commands (['a', 'b']).
  wmBindings = import ./wm-bindings.nix;
  renderCmd = c: if lib.isList c then "[" + lib.concatMapStringsSep ", " (x: "'${x}'") c + "]" else "'${c}'";
  renderBinds =
    binds: lib.concatStrings (lib.mapAttrsToList (chord: cmd: "${chord} = ${renderCmd cmd}\n") binds);
  sectionBinds = section: lib.concatMapStrings (
    it: lib.optionalString (it ? binds) (renderBinds it.binds)
  ) section.items;
  bindingsForMode = mode: lib.concatMapStrings sectionBinds (
    lib.filter (s: (s.mode or "main") == mode) wmBindings
  );
  # Resolve @HOME@/@BIN@ here: builtins.replaceStrings makes one non-rescanning
  # pass, so tokens these rendered lines introduce wouldn't be caught by the
  # outer substitution below.
  subTokens = builtins.replaceStrings [ "@HOME@" "@BIN@" ] [ homeDir binDir ];
  mainStatic = subTokens (bindingsForMode "main");
  serviceStatic = subTokens (bindingsForMode "service");

  # ⌥⇧<key> throws a window to an app's workspace. Skip keys already bound in
  # main mode by a non-app action (r = resort-windows).
  reservedMoveKeys = [ "r" ];
  isRealAssign = a: a.appId != null && a.workspace != null && a.appId != "com.mitchellh.ghostty";
  launchInvocation = a: ''${launchSh} "${a.name}"'' + lib.optionalString (a.workspace != null) " ${a.workspace}";

  mainMoves = lib.concatMapStrings (
    a:
    lib.optionalString (a.workspace != null && !(lib.elem a.key reservedMoveKeys))
      "alt-shift-${a.key} = 'move-node-to-workspace ${a.workspace}'\n"
  ) apps;

  launchLetters = lib.concatMapStrings (
    a: "${a.key} = ['exec-and-forget ${launchInvocation a}', 'mode main']\n"
  ) apps;

  windowRules = lib.concatMapStrings (
    a:
    lib.optionalString (isRealAssign a)
      "[[on-window-detected]]\nif.app-id = '${a.appId}'\nrun = 'move-node-to-workspace ${a.workspace}'\n\n"
  ) apps;

  resortCases = lib.concatMapStrings (
    a: lib.optionalString (isRealAssign a) ''        ${a.appId}) target="${a.workspace}" ;;''
    + lib.optionalString (isRealAssign a) "\n"
  ) apps;

  aerospaceToml = builtins.replaceStrings
    [ "@HOME@" "@BIN@" "@MAIN_STATIC@" "@SERVICE_STATIC@" "@MAIN_MOVES@" "@LAUNCH_LETTERS@" "@WINDOW_RULES@" ]
    [ homeDir binDir mainStatic serviceStatic mainMoves launchLetters windowRules ]
    (builtins.readFile ./aerospace.toml);

  resortScript = builtins.replaceStrings [ "@RESORT_CASES@" ] [ resortCases ] (
    builtins.readFile ./scripts/resort-windows.sh
  );

  # Any roster app with a cask installs itself — declaring the app also brings it.
  rosterCasks = lib.filter (c: c != null) (map (a: a.cask) apps);
in
lib.mkIf config.nebelhaus.prowl.enable {
  # Fold the JSON roster file into the roster option. List options concatenate
  # across definitions, so this appends to the host's hand-written apps; every
  # reader of nebelhaus.prowl.apps (here, sill, pounce) then sees both.
  nebelhaus.prowl.apps = fileApps;

  # AeroSpace itself (cask) + its tap. Roster apps that name a cask ride along.
  # Merged into den's homebrew config.
  homebrew.taps = [ "nikitabobko/tap" ];
  homebrew.casks = [ "aerospace" ] ++ rosterCasks;

  # Caps Lock → F18, feeding AeroSpace's `launch` leader mode. Decimal values are
  # the hidutil HID usage codes (caps lock → F18).
  system.keyboard.enableKeyMapping = true;
  system.keyboard.userKeyMapping = [
    {
      HIDKeyboardModifierMappingSrc = 30064771129; # 0x700000039 caps lock
      HIDKeyboardModifierMappingDst = 30064771181; # 0x70000006D F18
    }
  ];

  launchd.user.agents.aerospace = {
    serviceConfig = {
      ProgramArguments = withGUIWait "/Applications/AeroSpace.app/Contents/MacOS/AeroSpace";
      KeepAlive = true;
      RunAtLoad = true;
      ProcessType = "Interactive";
      StandardOutPath = "/tmp/aerospace.out.log";
      StandardErrorPath = "/tmp/aerospace.err.log";
      EnvironmentVariables = {
        LANG = "en_US.UTF-8";
        PATH = userPath;
      };
    };
  };

  # On wake, re-sort AeroSpace windows back to their assigned workspaces (macOS
  # otherwise dumps them all onto the current workspace).
  launchd.user.agents.sleepwatcher = {
    serviceConfig = {
      ProgramArguments = [
        "${pkgs.sleepwatcher}/bin/sleepwatcher"
        "-w"
        "/Users/${username}/.config/aerospace/on-wake.sh"
      ];
      KeepAlive = true;
      RunAtLoad = true;
      StandardOutPath = "/tmp/sleepwatcher.out.log";
      StandardErrorPath = "/tmp/sleepwatcher.err.log";
      EnvironmentVariables.PATH = userPath;
    };
  };

  home-manager.users.${username}.home.file = {
    ".config/aerospace/aerospace.toml" = {
      text = aerospaceToml;
      # AeroSpace runs as a KeepAlive launchd agent, so a rebuild rewrites this
      # file but the live daemon keeps its old in-memory bindings until it's
      # told to reload. Without this, every binding edit silently fails to take
      # until a manual `aerospace reload-config` or a reboot — which is exactly
      # how the caps→1-4 workspace focus binds looked "broken" after landing.
      # Guarded so first-boot activation (no daemon yet) doesn't fail; launchd
      # RunAtLoad then starts AeroSpace with the fresh config anyway.
      onChange = ''
        /opt/homebrew/bin/aerospace reload-config 2>/dev/null || true
      '';
    };
    ".config/aerospace/resort-windows.sh" = {
      text = resortScript;
      executable = true;
    };
    # caps→z reopen-last-closed-app: pops the stack sill's last_closed_app.sh
    # plugin fills on every app quit, and `open -b`s it back (browser ⌘⇧T analog).
    ".config/aerospace/reopen-last-app.sh" = {
      source = ./scripts/reopen-last-app.sh;
      executable = true;
    };
    ".config/aerospace/on-wake.sh" = {
      source = ./scripts/on-wake.sh;
      executable = true;
    };
    ".config/aerospace/launch.sh" = {
      source = ./scripts/launch.sh;
      executable = true;
    };
  };
}
