# Den — the foundation the rest of the house rests on. macOS system defaults,
# the Homebrew framework, core CLI tools, fonts, and periodic GC.
{
  config,
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

  # Homebrew's tap-trust check is flaky under sudo-driven activation (the
  # per-user trust store gets bypassed), so third-party taps fail with "Refusing
  # to load cask … from untrusted tap". We curate our taps ourselves; disable the
  # requirement globally via a brew.env that `bin/brew` reads on every call.
  environment.etc."homebrew/brew.env".text = ''
    HOMEBREW_NO_REQUIRE_TAP_TRUST=1
  '';

  # ---- macOS defaults -------------------------------------------------------
  system.defaults = {
    dock = {
      autohide = true;
      show-recents = false;
      mru-spaces = false;
      orientation = "bottom";
    };
    finder = {
      AppleShowAllExtensions = true;
      AppleShowAllFiles = true;
      FXPreferredViewStyle = "Nlsv"; # list view
      ShowPathbar = true;
      ShowStatusBar = true;
    };
    NSGlobalDomain = {
      ApplePressAndHoldEnabled = false; # key repeat, not the accent picker
      KeyRepeat = 2;
      InitialKeyRepeat = 15;
      AppleShowAllExtensions = true;
      # Hide the stock menu bar only when Sill draws its own; otherwise keep it.
      _HIHideMenuBar = config.nebelhaus.sill.enable;
    };
    trackpad = {
      Clicking = true;
      TrackpadRightClick = true;
      TrackpadThreeFingerDrag = true;
    };
    CustomUserPreferences."com.apple.commerce".AutoUpdate = true;
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
