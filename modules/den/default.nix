# Den — the foundation the rest of the house rests on. macOS system defaults,
# the Homebrew framework, core CLI tools, fonts, and periodic GC.
{
  config,
  lib,
  pkgs,
  username,
  ...
}:

{
  system.primaryUser = username;

  programs.zsh.enable = true;

  # Core CLI tools. The shell *experience* (aliases, starship, git, yazi, …) is
  # yours to add in your host file; these are the baseline binaries the rice and
  # its commands lean on.
  environment.systemPackages = with pkgs; [
    bat
    fzf
    delta
    gh
    glow
    gnupg
    jq
    lazygit
    lsd
    fastfetch
    tree
    ttyd
    # The everyday end-user CLI: haus rebuild / update / rollback / status /
    # edit / doctor — so a nebelhaus machine never needs raw nix incantations.
    # System-wide (not home-manager) so sudo and non-login shells see it too.
    # (The workshop's developer CLI is `bench` — a different name on purpose,
    # so the two never shadow each other.)
    (writeShellScriptBin "haus" (builtins.readFile ./haus.sh))
  ];

  # ---- Homebrew framework ---------------------------------------------------
  # den owns the framework + policy; feature modules (prowl, sill) contribute
  # their own taps/casks/brews, which nix-darwin merges into these lists.
  homebrew = {
    enable = true;
    onActivation = {
      # Policy is host-tunable (see modules/options.nix). Safe defaults: never
      # auto-update/upgrade (keeps rebuilds reproducible) and never delete
      # undeclared casks (cleanup = "none") so the rice can't eat an app you
      # installed yourself. A declarative-minded host can opt into "zap".
      inherit (config.nebelhaus.homebrew) autoUpdate upgrade cleanup;
    };

    # A minimal, opinionated starter set. Edit freely in your host file —
    # `homebrew.casks = [ ... ];` merges with whatever the modules declare.
    casks = [
      "ghostty" # the terminal the rice is themed for
    ];
  };

  # ---- Fonts ----------------------------------------------------------------
  # The rice's terminal font. JetBrains Mono Nerd Font carries the powerline +
  # icon glyphs that starship, lsd, and yazi draw with — without a Nerd Font
  # they render as tofu. hearth points Ghostty at it. `fonts.packages` is a list
  # option, so this merges with the sketchybar-app-font sill installs.
  fonts.packages = [ pkgs.nerd-fonts.jetbrains-mono ];

  # Homebrew's tap-trust check is flaky under sudo-driven activation (the
  # per-user trust store gets bypassed), so third-party taps fail with "Refusing
  # to load cask … from untrusted tap". We curate our taps ourselves; disable the
  # requirement globally via a brew.env that `bin/brew` reads on every call.
  environment.etc."homebrew/brew.env".text = ''
    HOMEBREW_NO_REQUIRE_TAP_TRUST=1
  '';

  # ---- macOS defaults -------------------------------------------------------
  # These are the rice's OPINIONS, so every value is lib.mkDefault: a host file
  # can override any of them with a plain value and win, no conflict. That's how
  # the bootstrap's "keep your current settings" capture works — it writes your
  # existing values into the host's system.defaults, overriding these. The one
  # exception is _HIHideMenuBar: it's not an opinion but a function of Sill (the
  # bar has to be hidden for Sill to replace it), so it stays rice-controlled.
  system.defaults = {
    dock = {
      autohide = lib.mkDefault true;
      show-recents = lib.mkDefault false;
      mru-spaces = lib.mkDefault false;
      orientation = lib.mkDefault "bottom";
    };
    finder = {
      AppleShowAllExtensions = lib.mkDefault true;
      AppleShowAllFiles = lib.mkDefault true;
      FXPreferredViewStyle = lib.mkDefault "Nlsv"; # list view
      ShowPathbar = lib.mkDefault true;
      ShowStatusBar = lib.mkDefault true;
    };
    NSGlobalDomain = {
      ApplePressAndHoldEnabled = lib.mkDefault false; # key repeat, not the accent picker
      KeyRepeat = lib.mkDefault 2;
      InitialKeyRepeat = lib.mkDefault 15;
      AppleShowAllExtensions = lib.mkDefault true;
      # Hide the stock menu bar only when Sill draws its own; otherwise keep it.
      # Rice-controlled (not mkDefault): it tracks sill.enable, not user taste.
      _HIHideMenuBar = config.nebelhaus.sill.enable;
    };
    trackpad = {
      Clicking = lib.mkDefault true;
      TrackpadRightClick = lib.mkDefault true;
      TrackpadThreeFingerDrag = lib.mkDefault true;
    };
    CustomUserPreferences."com.apple.commerce".AutoUpdate = lib.mkDefault true;
  };

  # ---- Nix housekeeping -----------------------------------------------------
  # Determinate owns the daemon + settings (/etc/nix/nix.custom.conf), so
  # nix-darwin's nix module is off. Determinate only GCs reactively under disk
  # pressure — on a big SSD that never fires — so run a weekly cleanup ourselves.
  nix.enable = false;
  launchd.daemons.nix-gc = {
    serviceConfig = {
      ProgramArguments = [
        "/nix/var/nix/profiles/default/bin/nix-collect-garbage"
        "--delete-older-than"
        "30d"
      ];
      StartCalendarInterval = [
        {
          Weekday = 0;
          Hour = 3;
          Minute = 0;
        }
      ];
      StandardOutPath = "/var/log/nix-gc.out.log";
      StandardErrorPath = "/var/log/nix-gc.err.log";
    };
  };

  nixpkgs.config.allowUnfree = true;
  nixpkgs.hostPlatform = "aarch64-darwin";
  system.stateVersion = 5;

  # Minimal home base so feature modules can layer `home.file` / packages on top.
  home-manager.users.${username}.home.stateVersion = "24.11";
}
