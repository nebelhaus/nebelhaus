# Hearth — the warm interior of the den. The terminal experience: zsh, a
# Nebelung-tinted starship prompt, git, and a themed CLI toolbelt (bat, delta,
# lazygit, lsd, yazi, zoxide, fzf), plus the ghostty / zellij / yazi dotfiles.
#
# Identity is NOT baked in: git name/email/signing come from `nebelhaus.git.*`
# (set in your host), and secrets stay out of the store — load them in your
# host's zsh initContent from ~/.secrets or similar.
{
  config,
  username,
  ...
}:

let
  gitCfg = config.nebelhaus.git;
  hearthCfg = config.nebelhaus.hearth;
in
{
  home-manager.users.${username} =
    {
      config,
      lib,
      pkgs,
      nebelung,
      ...
    }:
    let
      # Yazi preview: pipe code/text through bat (via piper) so previews match
      # the catppuccin-themed `cat` alias — colours + line numbers.
      batPreviewer = ''piper -- bat --color=always --paging=never --style=numbers --tabs=2 --terminal-width=$w "$1"'';

      # Nebelung glamour port (markdown styling for glow). glow ignores
      # $GLAMOUR_STYLE in its default "auto" mode (glow 2.x), so the style must
      # be passed explicitly with `-s`: baked into the yazi previewer plugin
      # (@glowStyle@ placeholder) and the `glow -p` opener below.
      glowStyle = "${nebelung.themes}/glow/catppuccin-mocha.json";
      glowPlugin = pkgs.runCommand "glow.yazi" { } ''
        cp -r ${./yazi/plugins/glow.yazi} $out
        chmod -R +w $out
        substituteInPlace $out/main.lua --subst-var-by glowStyle ${glowStyle}
      '';

      # Zen browser accent. Mauve is the family default (matches lazygit/yazi);
      # the nebelung zen port renders every accent under themes/Mocha/<Accent>/.
      zenAccent = "Mauve";
      zenTheme = "${nebelung.themes}/zen/themes/Mocha/${zenAccent}";

      # Option+Click a path in zellij → new tab cwd'd there. A fork of
      # zellij's built-in `link` plugin (see zellij/link-handler/), cross-built
      # to wasm32-wasip1 the same way nixpkgs builds its zellijPlugins.
      linkHandler = pkgs.pkgsCross.wasi32.callPackage ./zellij/link-handler { };
    in
    {
      home.sessionVariables = {
        CLICOLOR = "1";
        HOMEBREW_NO_ENV_HINTS = "1";
      };

      # A lean terminal/dev toolbelt. Personal choices (AI CLIs, orbstack, your
      # language toolchains) belong in your host file, not the public rice.
      home.packages = with pkgs; [
        bun
        fnm # node version manager (used by the initContent below)
        nixfmt-rfc-style
        glow # markdown renderer; yazi's glow previewer shells out to it
        mdcat
        fd # fast finder; used by yazi/zoxide navigation
        iina
        opencode
      ];

      programs.zsh = {
        enable = true;
        enableCompletion = true;
        autosuggestion.enable = true;
        syntaxHighlighting.enable = true;

        shellAliases = {
          cat = "bat --style=header,grid --tabs=2";
          ls = "lsd";
          lg = "lazygit";
        };

        history = {
          size = 5000;
          save = 5000;
          ignoreDups = true;
          ignoreSpace = true;
          path = "$HOME/.zsh_history";
        };

        historySubstringSearch.enable = true;

        oh-my-zsh = {
          enable = true;
          plugins = [
            "git"
            "sudo"
            "command-not-found"
          ];
        };

        plugins = [
          {
            name = "fzf-tab";
            src = pkgs.zsh-fzf-tab;
            file = "share/fzf-tab/fzf-tab.plugin.zsh";
          }
        ];

        initContent = lib.mkMerge [
          (lib.mkBefore ''
            export GPG_TTY=$(tty)

            # Homebrew (Apple Silicon)
            eval "$(/opt/homebrew/bin/brew shellenv)"

            # Load your secrets here in your HOST file (this is the public rice):
            #   export SOME_API_KEY="$(cat ~/.secrets/some-key)"
          '')
          ''
            # Nebelung zsh-syntax-highlighting colours (replaces catppuccin's
            # port). Sourced before the plugin loads — like catppuccin did —
            # which is fine: ZSH_HIGHLIGHT_STYLES is read at highlight time.
            source ${nebelung.themes}/zsh-syntax-highlighting/themes/catppuccin_mocha-zsh-syntax-highlighting.zsh

            # Custom completions
            fpath=(~/.zsh-completions $fpath)

            # fnm (Node version manager)
            export PATH="$HOME/.fnm:$PATH"
            eval "$(fnm env --use-on-cd --shell zsh)"

            bindkey -e

            setopt appendhistory
            setopt sharehistory
            setopt hist_ignore_space
            setopt hist_ignore_all_dups
            setopt hist_save_no_dups
            setopt hist_ignore_dups
            setopt hist_find_no_dups

            zstyle ':completion:*' matcher-list 'm:{a-z}={A-Za-z}'
            zstyle ':completion:*' list-colors "''${(s.:.)LS_COLORS}"
            zstyle ':completion:*' menu no

            # Auto-name the current zellij tab after the repo whenever you cd.
            if [[ -n "$ZELLIJ" ]]; then
              _zj_name_tab() {
                local root name
                root=$(git rev-parse --show-toplevel 2>/dev/null)
                name=''${''${root:-$PWD}:t}
                command zellij action rename-tab "$name" 2>/dev/null
              }
              autoload -Uz add-zsh-hook
              add-zsh-hook chpwd _zj_name_tab
            fi
          ''
        ];
      };

      # Starship, tinted with the Nebelung palette instead of stock mocha (the
      # whiskers starship port emits exactly this [palettes.catppuccin_mocha]
      # table; we inject the same name->#hex map so there's no duplication).
      programs.starship = {
        enable = true;
        enableZshIntegration = true;
        settings = {
          gcloud.disabled = true;
          palette = "catppuccin_mocha";
          palettes.catppuccin_mocha = nebelung.palette;
        };
      };

      # Git — identity comes from nebelhaus.git.* (your host sets it).
      programs.git = {
        enable = true;

        # Nebelung delta theme: defines [delta "catppuccin-mocha"] (referenced by
        # programs.delta.options.features below). Rendered by whiskers in the
        # nebelung flake; replaces the catppuccin.delta module's include.
        includes = [ { path = "${nebelung.themes}/delta/catppuccin.gitconfig"; } ];
        signing = lib.mkIf (gitCfg.signingKey != "") {
          key = gitCfg.signingKey;
          signByDefault = true;
        };
        settings = {
          user.name = gitCfg.name;
          user.email = gitCfg.email;
          color.ui = "auto";
          push.autoSetupRemote = true;
          tag.gpgSign = gitCfg.signingKey != "";
        };
      };

      programs.delta = {
        enable = true;
        enableGitIntegration = true;
        options = {
          side-by-side = false;
          line-numbers = true;
          # Nebelung delta styles: the [delta "catppuccin-mocha"] feature is
          # defined in the whiskers-rendered gitconfig included via
          # programs.git.includes above. Its syntax-theme points at the
          # "Catppuccin Mocha" bat theme, now rendered in Nebelung colours.
          features = "catppuccin-mocha";
        };
      };

      # Nebelung theme (mauve accent) injected straight into settings from
      # nebelung.palette — mirrors catppuccin/lazygit's mocha theme in Nebelung
      # colours (see the lazygit port in the nebelung repo for the file form).
      programs.lazygit = {
        enable = true;
        settings.gui = {
          theme = {
            activeBorderColor = [
              nebelung.palette.mauve
              "bold"
            ];
            inactiveBorderColor = [ nebelung.palette.subtext0 ];
            searchingActiveBorderColor = [ nebelung.palette.yellow ];
            optionsTextColor = [ nebelung.palette.blue ];
            selectedLineBgColor = [ nebelung.palette.surface0 ];
            inactiveViewSelectedLineBgColor = [ nebelung.palette.overlay0 ];
            cherryPickedCommitFgColor = [ nebelung.palette.mauve ];
            cherryPickedCommitBgColor = [ nebelung.palette.surface1 ];
            markedBaseCommitFgColor = [ nebelung.palette.blue ];
            markedBaseCommitBgColor = [ nebelung.palette.yellow ];
            unstagedChangesColor = [ nebelung.palette.red ];
            defaultFgColor = [ nebelung.palette.text ];
          };
          authorColors."*" = nebelung.palette.lavender;
        };
      };

      programs.lsd.enable = true;
      programs.lsd.enableZshIntegration = false;

      # Theme is the Nebelung-coloured "Catppuccin Mocha" tmTheme from the
      # nebelung flake (name kept so delta's syntax-theme + yazi's syntect_theme
      # references stay valid). programs.bat.themes rebuilds the bat cache on
      # activation so it is picked up.
      programs.bat = {
        enable = true;
        config = {
          style = "header,grid";
          tabs = "2";
          theme = "Catppuccin Mocha";
        };
        themes."Catppuccin Mocha" = {
          src = "${nebelung.themes}/bat/themes";
          file = "Catppuccin Mocha.tmTheme";
        };
      };

      programs.yazi = {
        enable = true;
        enableZshIntegration = true;
        shellWrapperName = "yy";
        settings.mgr.show_hidden = true;
        settings.mgr.ratio = [
          1
          4
          4
        ];
        plugins = {
          # Vendored: nixpkgs' glow plugin still uses the pre-26 Lua API and
          # crashes on yazi 26.x. This copy ports it to the current API, and
          # bakes the Nebelung glamour style path in (glowPlugin, see the let).
          glow = glowPlugin;
          piper = pkgs.yaziPlugins.piper;
          # Vendored (not in nixpkgs yet): copy the hovered/selected file(s)'
          # contents — not their path — to the clipboard. `setup` makes
          # home-manager emit the require(...):setup() call in init.lua;
          # notification = a toast on copy so there's UI feedback.
          copy-file-contents = {
            package = ./yazi/plugins/copy-file-contents.yazi;
            setup = true;
            settings = {
              append_char = "\n";
              notification = true;
            };
          };
        };
        keymap.mgr.prepend_keymap = [
          {
            on = "<Esc>";
            run = "quit";
            desc = "Close the peek browser";
          }
          {
            # cmd+c can't reach a TUI (the terminal eats the Cmd modifier), so
            # copy-contents lives on Y. `desc` surfaces it in yazi's help (~).
            on = "Y";
            run = "plugin copy-file-contents";
            desc = "Copy file contents to clipboard";
          }
        ];
        settings.plugin.prepend_previewers = [
          {
            url = "*.md";
            run = "glow";
          }
          {
            url = "*.mdx";
            run = "glow";
          }
          {
            mime = "text/*";
            run = batPreviewer;
          }
          {
            mime = "*/{xml,javascript,x-wine-extension-ini}";
            run = batPreviewer;
          }
          {
            mime = "application/{json,ndjson}";
            run = batPreviewer;
          }
        ];
        settings.opener = {
          read = [
            {
              run = ''glow -s "${glowStyle}" -p "$@"'';
              block = true;
              desc = "glow";
            }
          ];
          pager = [
            {
              run = ''bat --style=full --paging=always "$@"'';
              block = true;
              desc = "bat";
            }
          ];
        };
        settings.open.rules = [
          {
            url = "*.md";
            use = "read";
          }
          {
            url = "*.mdx";
            use = "read";
          }
          {
            url = "*";
            use = "pager";
          }
        ];
      };

      programs.zoxide = {
        enable = true;
        enableZshIntegration = true;
      };

      # Nebelung colours injected from nebelung.palette (matches catppuccin/fzf's
      # mocha --color mapping, blue muted out). home-manager turns these into the
      # --color flags in FZF_DEFAULT_OPTS.
      programs.fzf = {
        enable = true;
        enableZshIntegration = true;
        colors = {
          "bg+" = nebelung.palette.surface0;
          "bg" = nebelung.palette.base;
          "spinner" = nebelung.palette.rosewater;
          "hl" = nebelung.palette.red;
          "fg" = nebelung.palette.text;
          "header" = nebelung.palette.red;
          "info" = nebelung.palette.mauve;
          "pointer" = nebelung.palette.rosewater;
          "marker" = nebelung.palette.lavender;
          "fg+" = nebelung.palette.text;
          "prompt" = nebelung.palette.mauve;
          "hl+" = nebelung.palette.red;
          "selected-bg" = nebelung.palette.surface1;
          "border" = nebelung.palette.overlay0;
          "label" = nebelung.palette.text;
        };
      };

      programs.zellij.enable = true;

      # Catppuccin: `catppuccin.flavor` is the single source of truth — every
      # integration follows it. Raw dotfiles nix can't inject into (ghostty
      # config, zellij config.kdl) name the flavor manually; keep them in sync.
      # Every port here is themed by Nebelung instead of stock catppuccin-mocha —
      # either by pointing the program at a whiskers-rendered file from the
      # nebelung flake (bat/delta/lsd/yazi), or by injecting nebelung.palette
      # colours straight into the program's settings (starship/fzf/lazygit).
      # Each catppuccin integration is disabled so it doesn't clobber our wiring.
      # Colours are Nebelung; the catppuccin-mocha *names* are kept (nebelung's
      # own convention — its ghostty output is literally catppuccin-mocha.conf).
      catppuccin.autoEnable = true;
      catppuccin.enable = true;
      catppuccin.flavor = "mocha";
      catppuccin.bat.enable = false;
      catppuccin.starship.enable = false;
      catppuccin.delta.enable = false;
      catppuccin.fzf.enable = false;
      catppuccin.glamour.enable = false; # GLAMOUR_STYLE wired to nebelung above
      catppuccin.lazygit.enable = false;
      catppuccin.lsd.enable = false;
      catppuccin.yazi.enable = false;
      catppuccin.zsh-syntax-highlighting.enable = false;
      catppuccin.zellij.enable = false; # managed as a raw dotfile below

      programs.nix-index = {
        enable = true;
        enableZshIntegration = true;
      };
      programs.nix-index-database.comma.enable = true;

      programs.home-manager.enable = true;

      # Zen browser — drop the Nebelung userChrome/userContent into every Zen
      # profile. Zen's chrome lives INSIDE the (randomly-named) browser profile,
      # not under XDG, so home.file can't target it — we symlink into each
      # Profiles/*/chrome at activation instead. Symlinks (not copies) so a
      # palette rebuild propagates like every other port. Also flips on Firefox's
      # legacy userChrome/userContent stylesheets, which fresh profiles ship off.
      # Zen isn't installed here (themed-but-manual); the loop no-ops if absent.
      home.activation.zenNebelung = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        zenProfiles="$HOME/Library/Application Support/zen/Profiles"
        if [ -d "$zenProfiles" ]; then
          for prof in "$zenProfiles"/*/; do
            [ -d "$prof" ] || continue
            chrome="$prof"chrome
            $DRY_RUN_CMD mkdir -p "$chrome"
            $DRY_RUN_CMD ln -sf "${zenTheme}/userChrome.css" "$chrome/userChrome.css"
            $DRY_RUN_CMD ln -sf "${zenTheme}/userContent.css" "$chrome/userContent.css"
            userjs="$prof"user.js
            if [ ! -e "$userjs" ] || ! ${pkgs.gnugrep}/bin/grep -qF \
                'toolkit.legacyUserProfileCustomizations.stylesheets' "$userjs"; then
              printf '%s\n' 'user_pref("toolkit.legacyUserProfileCustomizations.stylesheets", true);' \
                | $DRY_RUN_CMD tee -a "$userjs" >/dev/null
            fi
          done
        fi
      '';

      # ---- dotfiles + Nebelung theme drops ----
      home.file = {
        # opencode
        ".config/opencode/themes/nebelung.json".source = "${nebelung.themes}/opencode/nebelung.json";
        ".config/opencode/tui.json".text = ''
          {
            "$schema": "https://opencode.ai/tui.json",
            "theme": "nebelung"
          }
        '';

        # ghostty (config lives in Application Support; theme lookup is XDG)
        "Library/Application Support/com.mitchellh.ghostty/config".source = ./ghostty/config;
        ".config/ghostty/themes/nebelung".source =
          "${nebelung.themes}/ghostty/themes/catppuccin-mocha.conf";

        # lsd colours (replaces catppuccin.lsd). lsd auto-reads this file.
        ".config/lsd/colors.yaml".source = "${nebelung.themes}/lsd/themes/catppuccin-mocha/colors.yaml";

        # yazi theme (replaces catppuccin.yazi): mgr/status/mode palette (mauve
        # accent) plus the syntect theme its syntect_theme line points at —
        # reusing the Nebelung bat tmTheme so previews match bat. The yazi-picker
        # theme.toml symlinks to this one, so it inherits Nebelung too.
        ".config/yazi/theme.toml".source =
          "${nebelung.themes}/yazi/themes/mocha/catppuccin-mocha-mauve.toml";
        ".config/yazi/Catppuccin-mocha.tmTheme".source =
          "${nebelung.themes}/bat/themes/Catppuccin Mocha.tmTheme";

        # zellij
        ".config/zellij/config.kdl".source = ./zellij/config.kdl;
        ".config/zellij/themes/nebelung.kdl".source = "${nebelung.themes}/zellij/themes/nebelung.kdl";
        ".config/zellij/layouts" = {
          source = ./zellij/layouts;
          recursive = true;
        };
        ".config/zellij/plugins/link-handler.wasm".source = "${linkHandler}/bin/link-handler.wasm";
        ".config/zellij/launch.sh" = {
          source = ./zellij/launch.sh;
          executable = true;
        };
        ".config/zellij/yazi-shell.sh" = {
          source = ./zellij/yazi-shell.sh;
          executable = true;
        };
        ".config/zellij/newtab.sh" = {
          source = ./zellij/newtab.sh;
          executable = true;
        };
        # Shortlist for the Super-Shift-t picker (nebelhaus.hearth.newTabDirs):
        # newtab.sh builds its picker view from this file, one home-relative
        # dir per line. Absent (option unset) = the picker browses all of $HOME.
        ".config/zellij/newtab-dirs" = lib.mkIf (hearthCfg.newTabDirs != [ ]) {
          text = lib.concatMapStrings (d: d + "\n") hearthCfg.newTabDirs;
        };
        ".config/zellij/copy-clean.pl" = {
          source = ./zellij/copy-clean.pl;
          executable = true;
        };

        # yazi new-tab picker (isolated config; shares theme.toml with main yazi)
        ".config/yazi-picker/yazi.toml".source = ./yazi/picker/yazi.toml;
        ".config/yazi-picker/keymap.toml".source = ./yazi/picker/keymap.toml;
        ".config/yazi-picker/theme.toml".source =
          config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/.config/yazi/theme.toml";
      };

      # zellij grants plugin permissions through an interactive prompt in the
      # plugin's pane — but link-handler is a background plugin (load_plugins)
      # with no pane, so the prompt is unreachable and an ungranted plugin
      # would sit event-less forever. Seed the grant straight into zellij's
      # permission cache instead (keyed by the plugin's expanded path). Append,
      # don't own the file: zellij rewrites it when other plugins are granted,
      # so a store symlink would break those; the grep guard keeps this
      # idempotent.
      home.activation.zellijLinkHandlerPermissions = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        permissions="$HOME/Library/Caches/org.Zellij-Contributors.Zellij/permissions.kdl"
        plugin="$HOME/.config/zellij/plugins/link-handler.wasm"
        if ! grep -qsF "\"$plugin\"" "$permissions"; then
          run mkdir -p "''${permissions%/*}"
          run sh -c 'printf "%s\n" \
            "\"$0\" {" \
            "    ReadApplicationState" \
            "    ChangeApplicationState" \
            "    FullHdAccess" \
            "    ReadSessionEnvironmentVariables" \
            "}" >> "$1"' "$plugin" "$permissions"
        fi
      '';
    };
}
