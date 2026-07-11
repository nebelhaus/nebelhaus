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

    hearth.editor = lib.mkOption {
      type = lib.types.str;
      default = "hx";
      example = "nvim";
      description = ''
        The ONE editor the rice uses everywhere. It's the shell command for
        $EDITOR / $VISUAL (git, etc.) AND what every "open in an editor" action
        launches — the "Nix Config" palette command, the bar's nix-open item,
        and the file-association hijack. Those open the target in a new zellij
        tab running this command, so a terminal editor (hx, nvim, vim, nano) is
        the natural fit for the rice; a GUI editor's CLI works too (e.g. "code"
        or "code -w" to block).
      '';
    };

    hearth.hijackFileAssociations = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        When true, build a small opener app and make it the default handler
        for common text/code extensions (json, md, ts, nix, …) via `duti`, so
        double-clicking those files opens them in nebelhaus.hearth.editor in a
        terminal. Off by default: silently rewriting your file associations is a
        jarring, hard-to-undo change, so it's strictly opt-in.
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

    theme.accent = lib.mkOption {
      type = lib.types.enum [
        "rosewater"
        "flamingo"
        "pink"
        "mauve"
        "red"
        "maroon"
        "peach"
        "yellow"
        "green"
        "teal"
        "sky"
        "sapphire"
        "blue"
        "lavender"
      ];
      default = "mauve";
      example = "sapphire";
      description = ''
        The accent colour, a Catppuccin Mocha name (the Nebelung palette is a
        grey-tinted Mocha). It recolours the tools nebelhaus injects colours
        into — lazygit, fzf, yazi, and the Zen browser — via the matching
        Nebelung per-accent ports.

        Honest scope: this moves the accent on those tools, NOT literally
        everything. Single-file dotfiles that bake the palette at their own
        theme slot (ghostty, starship, tmux, bat, zellij, …) keep their built-in
        colour and don't follow this option. The base palette stays the same
        Nebelung grey either way — only the accent hue changes.
      '';
    };

    theme.wallpaper = lib.mkOption {
      type = lib.types.enum [
        "none"
        "orbits"
        "constellation"
        "flow"
        "bold"
      ];
      default = "none";
      example = "orbits";
      description = ''
        The desktop wallpaper, set at each home-manager activation (osascript,
        every desktop on the current Space). Four Nebelung looks:

          orbits · constellation · flow  hand-made, the palette baked in
          bold                           generated from theme.accent, so it
                                         follows the accent (a bold pink at
                                         accent = "pink")

        Default "none" leaves your current wallpaper alone — changing the
        desktop is visible and personal, so nothing moves unless you ask (the
        bootstrap interview offers the choice on a fresh install).
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
                launch/focus it. Must be unique across the roster.
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
                it. null makes the app "launcher-only": the leader still opens
                it in the current workspace, but it claims no workspace, pill,
                or auto-assign rule (e.g. Passwords).
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
        wires an app into AeroSpace (leader key, workspace + window
        auto-assign), SketchyBar (a workspace pill), and the pounce cheatsheet,
        so those three configs never drift. Set your own roster in your host
        file; the default is a neutral terminal + browser so a fresh install
        boots to something that works. See modules/prowl for the generation.
      '';
    };

    # ---- optional rooms ----
    # den + hearth + collar are always on (system, shell, Touch ID). These three
    # are the choosable rooms — turning one off drops its packages, agents, and
    # config entirely (the "minimal vs developer" difference is just these flags).
    prowl.enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "AeroSpace tiling window management + the Caps-Lock leader launcher.";
    };
    sill.enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        The SketchyBar menu bar. When off, the native macOS menu bar is kept
        (nebelhaus stops hiding it) and no bar is drawn.
      '';
    };
    pounce.enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "The pounce command palette daemon (⌘Space) + its rice commands.";
    };

    sill.plugins = lib.mkOption {
      type = lib.types.listOf (
        lib.types.enum [
          "agents"
          "elgato"
          "harvest"
        ]
      );
      default = [ ];
      example = [ "elgato" ];
      description = ''
        Opt-in personal SketchyBar items, off by default because each targets one
        person's workflow/hardware/service and errors (or shows a dead pill)
        anywhere else:
          - "agents":  a paw pill tracking your `claude --worktree` agent panes —
                       amber when one is blocked on you, click for the per-agent
                       list; left-click a row to jump to that pane (focus its
                       zellij tab + raise the terminal window), ⌥/right-click for
                       a live `zellij subscribe` peek instead. Fed by Claude Code
                       hooks (wire them in your host's settings.json to point at
                       ~/.config/sketchybar/plugins/agents-hook.sh); dormant until
                       they fire, so it's harmless if you don't use agents.
          - "elgato":  toggles an Elgato Key Light on the local network.
          - "harvest": a Harvest time-tracking pill; needs a
                       ~/.config/sketchybar/harvest_secrets.sh you provide.
        The generic items (clock, battery, wifi, weather, media, cpu/mem, …) are
        always shown; only these are gated.
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

    # ---- hush ----
    hush.enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        The hush room: one quiet switch — bar pill, palette command, and a
        `hush` CLI — that turns macOS Do Not Disturb on/off (via the
        declaratively-bound symbolic hotkey 175, pressed synthetically),
        optionally sets your Slack status, and runs your hooks.

        Honest scope: hush flips the built-in Do Not Disturb, not named Focus
        modes, and it doesn't manage which apps break through — curate that
        once in System Settings. The keypress needs an Accessibility grant on
        whatever app invokes hush (palette runs inherit pounce's; grant
        sketchybar once for the pill). `hush doctor` walks the one-time steps.
      '';
    };

    hush.slack = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = ''
          Also set a Slack status and snooze Slack notifications (all devices,
          phone included) while hushed. Off by default: it needs a personal
          Slack user token (scopes users.profile:write + dnd:write) provided
          via tokenCommand. The previous status is saved and restored on
          unhush.
        '';
      };
      tokenCommand = lib.mkOption {
        type = lib.types.str;
        default = "";
        example = "security find-generic-password -s hush-slack -w";
        description = ''
          Shell command that prints the Slack user token (xoxp-…) to stdout.
          Keychain-first so no secret ever lands in the store or a dotfile:
            security add-generic-password -s hush-slack -a $USER -w 'xoxp-…'
        '';
      };
      statusText = lib.mkOption {
        type = lib.types.str;
        default = "heads down";
        description = "Slack status text while hushed.";
      };
      statusEmoji = lib.mkOption {
        type = lib.types.str;
        default = ":no_bell:";
        description = "Slack status emoji while hushed.";
      };
      snooze = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = ''
          Also pause Slack's own notifications (dnd.setSnooze) while hushed —
          this is what silences the phone. Ended on unhush; capped at 24h as
          a failsafe if you forget.
        '';
      };
    };

    hush.hooks = lib.mkOption {
      type = lib.types.listOf (lib.types.either lib.types.path lib.types.str);
      default = [ ];
      example = lib.literalExpression ''[ ./onair-light.sh "/Users/ada/bin/pause-music" ]'';
      description = ''
        Extra scripts run on every hush/unhush, each called with a single
        argument "on" or "off". Paths are copied into the store; strings are
        run as-is (so $HOME paths work). Failures are logged, never fatal —
        a broken hook can't wedge the toggle.
      '';
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
