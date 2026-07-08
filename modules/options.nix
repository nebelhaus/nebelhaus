# Host-provided identity. These are the values that are personal to YOU rather
# than part of the rice — a host file (see hosts/example) sets them.
{ lib, ... }:

{
  options.nebelhaus = {
    git = {
      name = lib.mkOption {
        type = lib.types.str;
        default = "";
        example = "Ada Lovelace";
        description = "Git user.name for commits (hearth wires it into home-manager).";
      };
      email = lib.mkOption {
        type = lib.types.str;
        default = "";
        example = "ada@example.com";
        description = "Git user.email for commits.";
      };
      signingKey = lib.mkOption {
        type = lib.types.str;
        default = "";
        example = "6F7BD6F43A7C1420";
        description = ''
          GPG key id for signing commits/tags. Empty disables commit signing.
          Key material + any YubiKey/smartcard setup live outside Nix
          (gpg-agent + pinentry-mac).
        '';
      };
    };

    hearth.newTabDirs = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      example = [
        "code"
        ".config"
      ];
      description = ''
        Home-relative directories the Super-Shift-t "new tab" yazi picker
        offers instead of all of $HOME. The picker opens on a view containing
        only these; navigating into them is normal yazi. Empty list keeps the
        default behaviour (browse $HOME). Only the picker is affected —
        regular yazi is untouched.
      '';
    };

    claude.globalMd = lib.mkOption {
      type = lib.types.lines;
      default = "";
      example = ''
        # CLAUDE.md — global
        How I like to work across every repo…
      '';
      description = ''
        Contents of Claude Code's global memory file, written to
        ~/.claude/CLAUDE.md (hearth wires it into home-manager). This is your
        personal, cross-project operating context — the rice ships no opinion of
        its own here, so leave it empty to manage ~/.claude/CLAUDE.md by hand.
      '';
    };

    prowl.apps = lib.mkOption {
      type = lib.types.listOf (
        lib.types.submodule {
          options = {
            key = lib.mkOption {
              type = lib.types.str;
              example = "s";
              description = ''
                The leader letter for this app: tap Caps Lock then this key to
                launch/focus it, or use the hyper chord (⌘⌥⌃⇧ + key). Must be
                unique across the roster.
              '';
            };
            name = lib.mkOption {
              type = lib.types.str;
              example = "Slack";
              description = "macOS application name, as passed to `open -a`.";
            };
            workspace = lib.mkOption {
              type = lib.types.nullOr lib.types.str;
              default = null;
              example = "S";
              description = ''
                The AeroSpace workspace this app owns — its window auto-moves
                here, it gets a SketchyBar pill, and ⌥⇧<key> throws a window to
                it. null makes the app "launcher-only": the leader/hyper chord
                still opens it in the current workspace, but it claims no
                workspace, pill, or auto-assign rule (e.g. Passwords).
              '';
            };
            appId = lib.mkOption {
              type = lib.types.nullOr lib.types.str;
              default = null;
              example = "com.tinyspeck.slackmacgap";
              description = ''
                Bundle id, used for the AeroSpace `on-window-detected`
                auto-assign rule and the wake-time re-sort. null skips
                auto-assignment (the app still launches, it just isn't herded
                to its workspace). Find one with `osascript -e 'id of app "…"'`.
              '';
            };
            barIcon = lib.mkOption {
              type = lib.types.nullOr lib.types.str;
              default = null;
              example = ":slack:";
              description = ''
                The SketchyBar workspace-pill glyph. A sketchybar-app-font
                ligature like ":slack:" renders the app's logo; any other
                string is drawn in the bar's Nerd Font. null falls back to the
                workspace letter. Ignored when workspace is null.
              '';
            };
            label = lib.mkOption {
              type = lib.types.nullOr lib.types.str;
              default = null;
              example = "Slack";
              description = "Cheatsheet caption for the leader key. null uses name.";
            };
            cask = lib.mkOption {
              type = lib.types.nullOr lib.types.str;
              default = null;
              example = "slack";
              description = ''
                Homebrew cask that installs this app. When set, it's appended to
                homebrew.casks so declaring the app also installs it. null means
                "already present / installed some other way" (e.g. Safari, Music).
              '';
            };
          };
        }
      );
      default = [
        {
          key = "t";
          name = "Ghostty";
          workspace = "T";
          appId = "com.mitchellh.ghostty";
          barIcon = ":ghostty:";
          label = "Ghostty (Terminal)";
        }
        {
          key = "b";
          name = "Zen";
          workspace = "B";
          appId = "app.zen-browser.zen";
          barIcon = ":zen_browser:";
          label = "Zen (Browser)";
          cask = "zen";
        }
      ];
      description = ''
        The app roster — ONE source of truth for the tiling launcher. Each entry
        wires an app into AeroSpace (leader key, hyper chord, workspace + window
        auto-assign), SketchyBar (a workspace pill), and the pounce cheatsheet,
        so those three configs never drift. Set your own roster in your host
        file; the default is a neutral terminal + browser so a fresh install
        boots to something that works. See modules/prowl for the generation.
      '';
    };

    sill.plugins = lib.mkOption {
      type = lib.types.listOf (
        lib.types.enum [
          "elgato"
          "harvest"
        ]
      );
      default = [ ];
      example = [ "elgato" ];
      description = ''
        Opt-in personal SketchyBar items, off by default because each targets
        one person's hardware/service and errors (or shows a dead pill) anywhere
        else:
          - "elgato":  toggles an Elgato Key Light on the local network.
          - "harvest": a Harvest time-tracking pill; needs a
                       ~/.config/sketchybar/harvest_secrets.sh you provide.
        The generic items (clock, battery, wifi, weather, media, cpu/mem, …) are
        always shown; only these two are gated.
      '';
    };

    homebrew = {
      cleanup = lib.mkOption {
        type = lib.types.enum [
          "none"
          "uninstall"
          "zap"
        ];
        default = "none";
        description = ''
          How `darwin-rebuild switch` treats Homebrew casks/brews that are
          installed but NOT declared anywhere in your config.

          - "none" (default, safe): leave undeclared formulae/casks alone. The
            rice never deletes apps you installed yourself.
          - "uninstall": remove undeclared formulae/casks (keeps their data).
          - "zap": remove undeclared formulae/casks AND their app data. Fully
            declarative, but a stray cask you forgot to list is deleted — with
            no backup — on the very next rebuild. Only choose this once every
            app you keep is declared (bootstrap can adopt your current casks).
        '';
      };
      autoUpdate = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = ''
          Run `brew update` before activating the Homebrew step on every
          rebuild. Off by default — reproducible rebuilds shouldn't silently
          pull newer formulae. Turn on if you want brew to track upstream.
        '';
      };
      upgrade = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = ''
          Upgrade outdated Homebrew packages on every rebuild. Off by default
          for the same reproducibility reason as autoUpdate.
        '';
      };
    };

    pounce.signingIdentity = lib.mkOption {
      type = lib.types.str;
      default = "";
      example = "DE2FB6DF7E66864C5F254DACF0AFC1B00685BA5D";
      description = ''
        SHA-1 of an Apple Development code-signing identity in your login
        keychain. The pounce daemon is re-signed with it so a macOS
        Accessibility (TCC) grant survives rebuilds. Find yours with:
          security find-identity -v -p codesigning
        Leave empty to run pounce unsigned (the palette works, but auto-paste
        and other Accessibility-gated features stay off).
      '';
    };
  };
}
