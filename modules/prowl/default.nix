# Prowl — stake out your screen. AeroSpace tiling, launched via nix-darwin
# (not Login Items) so it survives cold boot, plus the Caps→F18 leader remap and
# a wake-time window re-sort.
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
  # AeroSpace itself (cask) + its tap. Merged into den's homebrew config.
  homebrew.taps = [ "nikitabobko/tap" ];
  homebrew.casks = [ "aerospace" ];

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
    ".config/aerospace/aerospace.toml".source = ./aerospace.toml;
    ".config/aerospace/resort-windows.sh" = {
      source = ./scripts/resort-windows.sh;
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
