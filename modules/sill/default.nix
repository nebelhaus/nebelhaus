# Sill — a windowsill for your menu bar. SketchyBar, launched via nix-darwin,
# with the stray-agent eviction that keeps a rogue `brew services` instance from
# stealing the lock file.
{
  pkgs,
  username,
  ...
}:

let
  withGUIWait = import ../lib/gui-wait.nix;
  userPath = "/run/current-system/sw/bin:/etc/profiles/per-user/${username}/bin:/opt/homebrew/bin:/opt/homebrew/sbin:/usr/bin:/bin:/usr/sbin:/sbin";
in
{
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

  home-manager.users.${username}.home.file = {
    ".config/sketchybar/sketchybarrc".source = ./sketchybar/sketchybarrc;
    ".config/sketchybar/aerospace-notify.sh".source = ./sketchybar/aerospace-notify.sh;
    ".config/sketchybar/plugins" = {
      source = ./sketchybar/plugins;
      recursive = true;
    };
  };
}
