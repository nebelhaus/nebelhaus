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
  hostname,
  ...
}:

let
  gitCfg = config.nebelhaus.git;
  hearthCfg = config.nebelhaus.hearth;
  claudeCfg = config.nebelhaus.claude;
  accent = config.nebelhaus.theme.accent; # a Catppuccin accent name, e.g. "mauve"
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

      # The accent colour (nebelhaus.theme.accent, default mauve) as the hex the
      # tools nebelhaus injects colours into use for their accent.
      accentColor = nebelung.palette.${accent};
      # Zen browser accent. The nebelung zen port renders every accent under
      # themes/Mocha/<Accent>/ (capitalised); yazi uses the lowercase name.
      zenAccent = lib.toUpper (lib.substring 0 1 accent) + lib.substring 1 (lib.stringLength accent) accent;
      zenTheme = "${nebelung.themes}/zen/themes/Mocha/${zenAccent}";

      # The zellij custom layout, rendered from the in-repo template. Only two
      # tokens remain: the login name for the tab-bar's username pill, and
      # $HOME for the plugin paths. Bar/tab colours no longer ride in here —
      # our tab-bar + status-bar plugins read the zellij "nebelung" theme
      # directly (the old zjstatus couldn't, so its colours used to be injected
      # here). Shared by custom.kdl and its $HOME-pinned home.kdl variant below.
      zellijLayout =
        builtins.replaceStrings [ "@username@" "@HOME@" ]
          [
            (builtins.substring 0 6 username)
            config.home.homeDirectory
          ]
          (builtins.readFile ./zellij/custom.kdl);

      # Seeds a zellij plugin's grants into the permission cache (see the
      # home.activation entries near the end of this file for the why).
      seedZellijPluginPermissions =
        wasm: perms:
        lib.hm.dag.entryAfter [ "writeBoundary" ] ''
          permissions="$HOME/Library/Caches/org.Zellij-Contributors.Zellij/permissions.kdl"
          plugin="$HOME/.config/zellij/plugins/${wasm}"
          run sh -c '
            permissions="$0" plugin="$1" tmp="$0.hm-seed"
            mkdir -p "''${permissions%/*}"
            if [ -f "$permissions" ]; then
              # /usr/bin path: home-manager activation runs with a bare PATH
              /usr/bin/awk -v open="\"$plugin\" {" \
                "\$0 == open { skip = 1; next } skip && \$0 == \"}\" { skip = 0; next } !skip" \
                "$permissions" > "$tmp"
            else
              : > "$tmp"
            fi
            printf "%s\n" \
              "\"$plugin\" {" \
              ${lib.concatMapStrings (p: "\"    ${p}\" \\\n              ") perms}"}" >> "$tmp"
            mv "$tmp" "$permissions"
          ' "$permissions" "$plugin"
        '';
    in
    {
      home.sessionVariables = {
        CLICOLOR = "1";
        HOMEBREW_NO_ENV_HINTS = "1";
        EDITOR = hearthCfg.editor;
        VISUAL = hearthCfg.editor;
      };

      # A lean terminal/dev toolbelt. Personal choices (AI CLIs, orbstack, your
      # language toolchains) belong in your host file, not the public rice.
      home.packages = with pkgs; [
        bun
        fnm # node version manager (used by the initContent below)
        nixfmt-rfc-style
        chafa # fast terminal image previewer / layout engine
        glow # markdown renderer; yazi's glow previewer shells out to it
        fd # fast finder; used by yazi/zoxide navigation
        iina
        duti
      ]
      # opencode has no x86_64-darwin build, so guard on the package's own
      # platform list rather than hardcoding an arch — it self-heals the day
      # upstream adds Intel, and keeps the example-intel eval green meanwhile.
      ++ lib.optional (lib.meta.availableOn pkgs.stdenv.hostPlatform pkgs.opencode) pkgs.opencode;

      programs.zsh = {
        enable = true;
        enableCompletion = true;
        autosuggestion.enable = true;
        syntaxHighlighting.enable = true;

        # ~/.zshenv — sourced by EVERY zsh (interactive or not, login or not),
        # before zshrc and before home-manager's zoxide init. Keeping _ZO_DOCTOR
        # here rather than in initContent means non-interactive shells (Claude
        # agents, anything that shells out) also silence zoxide's false-positive
        # doctor warning — zshrc is interactive-only, so it never reached them.
        envExtra = ''
          export _ZO_DOCTOR=0
        '';

        shellAliases = {
          c = "claude";
          cat = "bat --style=header,grid --tabs=2";
          ls = "lsd";
          lg = "lazygit";
          # mdcat's replacement: the same themed glow yazi's previewer uses, so
          # a terminal `mdcat file.md` renders markdown identically to the yazi
          # right-pane preview (Nebelung glamour port, tables and all).
          mdcat = ''glow -s "${glowStyle}"'';
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

            # zoxide's doctor wants its init to be the LAST thing in the zshrc,
            # but home-manager injects `zoxide init` early — and we deliberately
            # add chpwd hooks after it (fnm --use-on-cd, the zellij tab-namer).
            # Those coexist fine with zoxide's `cd` override (see programs.zoxide
            # below), so the doctor is a false positive; it's silenced via
            # _ZO_DOCTOR=0 in the envExtra above (~/.zshenv) so agent shells —
            # which never source the interactive-only zshrc — get it too.

            # Homebrew (Apple Silicon)
            eval "$(/opt/homebrew/bin/brew shellenv)"

            # Secrets: prefer secretspec (ships with the rice) — a project
            # declares its secrets in a committed secretspec.toml and
            # `secretspec run -- cmd` injects the values from your provider
            # (nebelhaus.secrets.provider) into just that process, nothing
            # plaintext on disk. Anything you truly need in EVERY shell,
            # export in your HOST file's initContent (this is the public rice).
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
              # New panes/tabs inherit the focused pane's cwd (Super p / Super t)
              # — which, next to a claude --worktree pane, is the agent's
              # throwaway checkout under ~/.cache/claude-worktrees. A fresh
              # interactive shell has no business starting there: hop to the repo
              # the worktree belongs to (the parent of the shared .git).
              # $CLAUDECODE spares the agent's own subshells, and $ZJ_STAY spares
              # the deliberate "stay here" spawns (Super Shift p, and the peek
              # Enter-on-dir tab) — those must stay in the worktree. Both fire
              # once at shell birth, so unset ZJ_STAY afterward to keep it out of
              # child processes and later cd's.
              if [[ -z "$CLAUDECODE" && -z "$ZJ_STAY" && "$PWD" == "$HOME/.cache/claude-worktrees/"* ]]; then
                _wt_main="$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null)"
                [[ -n "$_wt_main" ]] && cd "''${_wt_main:h}"
                unset _wt_main
              fi
              unset ZJ_STAY

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
              accentColor
              "bold"
            ];
            inactiveBorderColor = [ nebelung.palette.subtext0 ];
            searchingActiveBorderColor = [ nebelung.palette.yellow ];
            optionsTextColor = [ nebelung.palette.blue ];
            selectedLineBgColor = [ nebelung.palette.surface0 ];
            inactiveViewSelectedLineBgColor = [ nebelung.palette.overlay0 ];
            cherryPickedCommitFgColor = [ accentColor ];
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
        # Default preview caps (600×900 px) leave kitty-protocol previews soft
        # on a retina display; size them for the near-fullscreen peek window.
        settings.preview.max_width = 2400;
        settings.preview.max_height = 1800;
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
          # peek-open: Enter inside the Super-y peek overlay. On a directory it
          # spawns a new zellij tab cwd'd there (the folded-in Super-Shift-t
          # picker); on a file it pages as normal. Gated on PEEK=1 (set only by
          # peek-run.sh), so in a plain `yy` session it's a no-op passthrough to
          # yazi's default Enter. See yazi/plugins/peek-open.yazi.
          peek-open.package = ./yazi/plugins/peek-open.yazi;
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
          {
            # Enter routes through peek-open: in the peek overlay a directory
            # opens a new zellij tab there, a file pages fullscreen; everywhere
            # else it's plain `open` (yazi's default Enter). See peek-open.yazi.
            on = "<Enter>";
            run = "plugin peek-open";
            desc = "Peek: open dir as tab / page file (else default open)";
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
          image_preview = [
            {
              run = ''~/.config/zellij/image-preview.sh "$@"'';
              block = true;
              desc = "Preview";
            }
          ];
          open = [
            {
              run = ''open "$@"'';
              orphan = true;
              desc = "Open";
            }
          ];
        };
        settings.open.rules = [
          {
            mime = "image/*";
            use = "image_preview";
          }
          {
            mime = "video/*";
            use = "open";
          }
          {
            mime = "audio/*";
            use = "open";
          }
          {
            mime = "application/pdf";
            use = "open";
          }
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
        # Let zoxide take over `cd`: `cd proj` jumps by frecency, `cdi` opens
        # the interactive fzf picker. The chpwd hooks below (zellij tab-naming)
        # still fire — zoxide's cd triggers the same chpwd event as builtin cd.
        options = [ "--cmd cd" ];
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
          "info" = accentColor;
          "pointer" = nebelung.palette.rosewater;
          "marker" = nebelung.palette.lavender;
          "fg+" = nebelung.palette.text;
          "prompt" = accentColor;
          "hl+" = nebelung.palette.red;
          "selected-bg" = nebelung.palette.surface1;
          "border" = nebelung.palette.overlay0;
          "label" = nebelung.palette.text;
        };
      };

      programs.helix = {
        enable = true;
        settings = {
          theme = "nebelung";
          editor = {
            line-number = "relative";
            mouse = true;
            cursorline = true;
            color-modes = true;
            cursor-shape = {
              normal = "block";
              insert = "bar";
              select = "underline";
            };
            file-picker = {
              hidden = false;
            };
            lsp = {
              display-messages = true;
            };
            statusline = {
              left = [
                "mode"
                "spinner"
              ];
              center = [ "file-name" ];
              right = [
                "diagnostics"
                "selections"
                "position"
                "file-encoding"
                "file-line-ending"
                "file-type"
              ];
              separator = "│";
              mode = {
                normal = "NORMAL";
                insert = "INSERT";
                select = "SELECT";
              };
            };
          };
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
      catppuccin.helix.enable = false;
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
        # Claude Code global memory — cross-project operating context, supplied
        # by the host via nebelhaus.claude.globalMd. Unset (option empty) = no
        # file written, so ~/.claude/CLAUDE.md stays hand-managed.
        ".claude/CLAUDE.md" = lib.mkIf (claudeCfg.globalMd != "") {
          text = claudeCfg.globalMd;
        };

        # opencode
        ".config/opencode/themes/nebelung.json".source = "${nebelung.themes}/opencode/nebelung.json";
        ".config/opencode/tui.json".text = ''
          {
            "$schema": "https://opencode.ai/tui.json",
            "theme": "nebelung"
          }
        '';

        # Helix nebelung theme
        ".config/helix/themes/nebelung.toml".text = ''
          inherits = "catppuccin_mocha"

          [palette]
          rosewater = "${nebelung.palette.rosewater}"
          flamingo = "${nebelung.palette.flamingo}"
          pink = "${nebelung.palette.pink}"
          mauve = "${nebelung.palette.mauve}"
          red = "${nebelung.palette.red}"
          maroon = "${nebelung.palette.maroon}"
          peach = "${nebelung.palette.peach}"
          yellow = "${nebelung.palette.yellow}"
          green = "${nebelung.palette.green}"
          teal = "${nebelung.palette.teal}"
          sky = "${nebelung.palette.sky}"
          sapphire = "${nebelung.palette.sapphire}"
          blue = "${nebelung.palette.blue}"
          lavender = "${nebelung.palette.lavender}"
          text = "${nebelung.palette.text}"
          subtext1 = "${nebelung.palette.subtext1}"
          subtext0 = "${nebelung.palette.subtext0}"
          overlay2 = "${nebelung.palette.overlay2}"
          overlay1 = "${nebelung.palette.overlay1}"
          overlay0 = "${nebelung.palette.overlay0}"
          surface2 = "${nebelung.palette.surface2}"
          surface1 = "${nebelung.palette.surface1}"
          surface0 = "${nebelung.palette.surface0}"
          base = "${nebelung.palette.base}"
          mantle = "${nebelung.palette.mantle}"
          crust = "${nebelung.palette.crust}"
        '';

        # ghostty (config lives in Application Support; theme lookup is XDG)
        # ghostty's `command` runs the zellij launcher by absolute path; render
        # @HOME@ → the user's home so it isn't pinned to one account.
        "Library/Application Support/com.mitchellh.ghostty/config".text =
          builtins.replaceStrings [ "@HOME@" ] [ config.home.homeDirectory ] (
            builtins.readFile ./ghostty/config
          );
        ".config/ghostty/themes/nebelung".source =
          "${nebelung.themes}/ghostty/themes/catppuccin-mocha.conf";

        # lsd colours (replaces catppuccin.lsd). lsd auto-reads this file.
        ".config/lsd/colors.yaml".source = "${nebelung.themes}/lsd/themes/catppuccin-mocha/colors.yaml";

        # yazi theme (replaces catppuccin.yazi): mgr/status/mode palette (mauve
        # accent) plus the syntect theme its syntect_theme line points at —
        # reusing the Nebelung bat tmTheme so previews match bat.
        ".config/yazi/theme.toml".source =
          "${nebelung.themes}/yazi/themes/mocha/catppuccin-mocha-${accent}.toml";
        ".config/yazi/Catppuccin-mocha.tmTheme".source =
          "${nebelung.themes}/bat/themes/Catppuccin Mocha.tmTheme";

        # zellij
        # config.kdl bakes absolute script paths (zellij doesn't expand $HOME in
        # copy_command / Run / layout), so render @HOME@ → the user's home.
        ".config/zellij/config.kdl".text = builtins.replaceStrings [ "@HOME@" ] [
          config.home.homeDirectory
        ] (builtins.readFile ./zellij/config.kdl);
        ".config/zellij/themes/nebelung.kdl".source = "${nebelung.themes}/zellij/themes/nebelung.kdl";
        # Custom layout, rendered from the in-repo template (see zellijLayout
        # in the let above).
        ".config/zellij/layouts/custom.kdl".text = zellijLayout;
        # The same layout with the content tab pinned to $HOME — the
        # Super-Shift-t NewTab bind opens tabs from this file, so a new tab
        # always starts at ~ no matter where the focused pane lives. Tab-level
        # cwd is the only form zellij honors under a default_tab_template
        # (peek-run.sh pulls the same trick per-pick); the assert trips at eval
        # time if custom.kdl's
        # content-tab line ever changes shape, instead of silently shipping a
        # layout that no-ops back to cwd inheritance.
        ".config/zellij/layouts/home.kdl".text =
          let
            pinned =
              builtins.replaceStrings [ "\n    tab {\n" ] [ "\n    tab cwd=\"${config.home.homeDirectory}\" {\n" ]
                zellijLayout;
          in
          assert pinned != zellijLayout;
          pinned;
        ".config/zellij/plugins/link-handler.wasm".source = ./zellij/plugins/zellij_link_handler.wasm;
        # tab-history (see zellij/tab-history/): background plugin that makes
        # Ctrl(+Shift)+Tab walk tabs in most-recently-used order (browser-style
        # back/forward) instead of by position. Loaded via config.kdl's
        # load_plugins; grants seeded below. Wasm vendored by its build.sh.
        ".config/zellij/plugins/tab-history.wasm".source = ./zellij/plugins/zellij_tab_history.wasm;
        # Our status-bar fork (see zellij/status-bar/): identical to the
        # built-in except the bottom-right quick hints also surface NewTab,
        # so Super-t shows next to Super-p. Wasm vendored by its build.sh.
        ".config/zellij/plugins/status-bar.wasm".source = ./zellij/plugins/zellij_status_bar.wasm;
        # Our tab-bar fork (see zellij/tab-bar/): the top bar, replacing the
        # third-party zjstatus that used to sit here. Same active-anchored tab
        # scroll viewport as upstream zellij:tab-bar (so tabs stay readable on a
        # thin pane instead of clipping under the right-hand widgets, which is
        # what zjstatus did), themed to nebelung, with a username pill + a
        # Ctrl+Tab / swap-layout right side. Wasm vendored by its build.sh.
        ".config/zellij/plugins/tab-bar.wasm".source = ./zellij/plugins/zellij_tab_bar.wasm;
        ".config/zellij/launch.sh" = {
          source = ./zellij/launch.sh;
          executable = true;
        };
        ".config/zellij/image-preview.sh" = {
          source = ./zellij/image-preview.sh;
          executable = true;
        };
        ".config/zellij/peek.sh" = {
          source = ./zellij/peek.sh;
          executable = true;
        };
        ".config/zellij/peek-run.sh" = {
          source = ./zellij/peek-run.sh;
          executable = true;
        };
        # The one floating-Ghostty helper (geom + spawn); peek.sh, the Rebuild
        # System pounce command, and the agent-peek popup all route through it.
        ".config/zellij/float-term.sh" = {
          source = ./zellij/float-term.sh;
          executable = true;
        };
        # The one "open in the editor" launcher — a new zellij tab running
        # nebelhaus.hearth.editor (baked into @editor@). Shared by the "Nix
        # Config" palette/bar commands and the file-association hijack.
        ".config/zellij/editor-open-pane.sh" = {
          text = builtins.replaceStrings [ "@editor@" ] [ hearthCfg.editor ] (
            builtins.readFile ./zellij/editor-open-pane.sh
          );
          executable = true;
        };
        # pounce's terminal launcher (POUNCE_TERMINAL_LAUNCHER, wired in
        # modules/pounce) — opens `ssh <host>` etc. in a new `main`-session tab,
        # same flow as editor-open-pane.sh above.
        ".config/zellij/pounce-terminal.sh" = {
          source = ./zellij/pounce-terminal.sh;
          executable = true;
        };
        # The one "open the nix config" opener — resolves this host's
        # hosts/@hostname@/default.nix and hands it to the launcher above with
        # the flake root as cwd. The "Nix Config" palette command (pounce) and
        # the bar's nix pill (sill) both exec this.
        ".config/zellij/nix-config-open.sh" = {
          text = builtins.replaceStrings [ "@hostname@" ] [ hostname ] (
            builtins.readFile ./zellij/nix-config-open.sh
          );
          executable = true;
        };
        ".config/zellij/yazi-shell.sh" = {
          source = ./zellij/yazi-shell.sh;
          executable = true;
        };
        ".config/zellij/copy-clean.pl" = {
          source = ./zellij/copy-clean.pl;
          executable = true;
        };
      };

      # zellij grants plugin permissions through an interactive (y/n) prompt in
      # the plugin's pane — but none of our forks can answer it: link-handler is
      # a background plugin (load_plugins) with no pane, status-bar never calls
      # request_permission (built-ins don't need to, and we keep the fork diff
      # minimal), and tab-bar's "pane" is a 1-line borderless bar you can't
      # select — so its prompt renders in the bar but no keystroke ever reaches
      # it. An ungranted plugin therefore sits event-less forever (zellij only
      # auto-grants when EVERY requested permission is cached).
      # Seed the grants straight into zellij's permission cache instead (keyed
      # by the plugin's expanded path): replace our plugin's block wholesale so
      # permission-list changes propagate, but never own the file — zellij
      # rewrites it when other plugins are granted interactively, so those
      # entries must survive.
      #
      # OPERATIONAL GOTCHA — a live server can clobber a fresh seed, and only a
      # bounce fixes it. zellij re-reads this file whenever a plugin requests
      # permission, so a seed normally takes effect on the next plugin load. But
      # a running server also *rewrites* the file from its own in-memory
      # snapshot (whenever any plugin is granted), which can drop a grant this
      # activation just wrote. So when a rebuild changes a bar plugin's wasm,
      # the next new tab can surface the un-answerable prompt above even though
      # the seed ran — the seed and the running server race for the file. The
      # seed alone can't win that race (zellij owns the file at runtime); the
      # fix is to bounce the server so it reloads the seeded file cleanly:
      #     zellij kill-session <name> && zellij attach --create <name>
      # serialize_pane_viewport is on, so pane layouts + scrollback resurrect
      # (live processes don't — re-run them). `bench try switch` (or any
      # rebuild) re-runs this seed; the bounce is what makes an already-running
      # server honour it.
      home.activation.zellijLinkHandlerPermissions = seedZellijPluginPermissions "link-handler.wasm" [
        "ReadApplicationState"
        "ChangeApplicationState"
        "FullHdAccess"
        "RunCommands"
        "ReadSessionEnvironmentVariables"
      ];
      # ModeUpdate/TabUpdate/PaneUpdate — everything the bar renders from —
      # are gated on ReadApplicationState (zellij's check_event_permission).
      home.activation.zellijStatusBarPermissions = seedZellijPluginPermissions "status-bar.wasm" [
        "ReadApplicationState"
      ];
      # tab-history reads TabUpdate (ReadApplicationState) to track focus order
      # and calls go_to_tab (ChangeApplicationState) to switch tabs; both are
      # pre-seeded because it's a background plugin with no pane to prompt in.
      home.activation.zellijTabHistoryPermissions = seedZellijPluginPermissions "tab-history.wasm" [
        "ReadApplicationState"
        "ChangeApplicationState"
      ];
      # tab-bar renders from TabUpdate/ModeUpdate (ReadApplicationState) and
      # switches tabs on a mouse click via switch_tab_to (ChangeApplicationState).
      # It's the top bar, so its prompt would render in a 1-line borderless pane
      # you can't select — un-answerable (see the note above), which is exactly
      # why it must be seeded rather than left to prompt on first run.
      home.activation.zellijTabBarPermissions = seedZellijPluginPermissions "tab-bar.wasm" [
        "ReadApplicationState"
        "ChangeApplicationState"
      ];

      # File-association hijack — opt-in (nebelhaus.hearth.hijackFileAssociations).
      # Off by default: silently making EditorOpen.app the handler for a dozen
      # extensions is a jarring, hard-to-undo surprise on someone else's machine.
      # It opens files in the rice editor (nebelhaus.hearth.editor) via the same
      # zellij launcher the palette/bar use.
      home.activation.editorOpenApp = lib.mkIf hearthCfg.hijackFileAssociations (
        lib.hm.dag.entryAfter [ "writeBoundary" ] ''
          appDir="$HOME/Applications"
          $DRY_RUN_CMD mkdir -p "$appDir"
          $DRY_RUN_CMD /usr/bin/osacompile -o "$appDir/EditorOpen.app" -e 'on open theFiles' -e 'repeat with theFile in theFiles' -e 'set file_path to POSIX path of theFile' -e 'do shell script "$HOME/.config/zellij/editor-open-pane.sh " & quoted form of file_path' -e 'end repeat' -e 'end open'
          $DRY_RUN_CMD /usr/bin/plutil -replace CFBundleIdentifier -string "org.nebelhaus.editoropen" "$appDir/EditorOpen.app/Contents/Info.plist"

          # Now set default handlers using duti. duti prints a LaunchServices
          # "error -50" (paramErr) when it sets a handler by bare extension —
          # a benign quirk on modern macOS: the mapping usually still takes, and
          # a failure here isn't worth aborting activation over. Swallow it so it
          # stops surfacing as scary trailing output during `bench try switch`.
          if [ -x "${pkgs.duti}/bin/duti" ]; then
            for ext in json txt md ts tsx js jsx yaml yml toml nix css sh; do
              $DRY_RUN_CMD "${pkgs.duti}/bin/duti" -s org.nebelhaus.editoropen "$ext" all 2>/dev/null || true
            done
          fi
        ''
      );

      # Claude Code — seed a couple of defaults into settings.json:
      #   permissions.defaultMode = "auto"  — pin the permission mode here
      #     instead of passing --dangerously-skip-permissions on the command
      #     line (the zellij binds above no longer do). "auto" runs agents
      #     unattended but keeps the background safety checks that block
      #     dangerous escalations, so it's safe on the host — unlike
      #     bypassPermissions, which is the flag's exact, check-free behaviour
      #     and wants a container.
      #   tui = "fullscreen"  — render Claude Code in the alt-screen (fullscreen)
      #     TUI rather than inline. `/tui fullscreen` sets this per-session and
      #     relaunches; seeding it makes fullscreen the default on every new
      #     machine. Highlight-to-copy through zellij still works, so there's no
      #     tradeoff to the classic inline renderer.
      #   disableAgentView = true  — turn off the built-in agent-manager view
      #     (`claude agents`, `--bg`, /background, its on-demand daemon) and the
      #     "← for agents" toolbar hint that advertises it. Undocumented key,
      #     equivalent to CLAUDE_CODE_DISABLE_AGENT_VIEW=1. Parallel Claude
      #     sessions here go through `wt` + zellij panes (den/hearth), not the
      #     in-app view, so the hint is pure noise — kill it at the rice level.
      #   statusLine  — point Claude Code's status bar at `claude-statusline`
      #     (den ships it on PATH). It renders THIS session's `wt` worktree +
      #     the sister worktrees in flight across every repo — the agent-worktree
      #     HUD the built-in bar can't give. refreshInterval keeps the sister
      #     list current while the main session sits idle watching other panes.
      #   spinnerTipsEnabled = false  — drop the rotating "Tip:" line under the
      #     spinner; the status bar already carries the context that matters.
      #     (The built-in mode/`esc to interrupt` footer badge has no such knob
      #     in Claude Code — statusLine renders above it and can't replace it.)
      # Claude owns settings.json (it rewrites the file as plugins/statusline/
      # permission grants change), so we merge our keys in at activation and
      # never own it — every other key it holds must survive. jq is pinned from
      # the store because activation runs with a bare PATH.
      home.activation.claudeCodeSettings = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        run sh -c '
          settings="$0"
          mkdir -p "''${settings%/*}"
          tmp="$settings.hm-seed"
          if [ -s "$settings" ]; then base="$settings"; else base="$tmp.base"; printf "{}" > "$base"; fi
          ${pkgs.jq}/bin/jq ".permissions.defaultMode = \"auto\"
            | .tui = \"fullscreen\"
            | .disableAgentView = true
            | .spinnerTipsEnabled = false
            | .statusLine = {type: \"command\", command: \"/run/current-system/sw/bin/claude-statusline\", refreshInterval: 12}" \
            "$base" > "$tmp"
          mv "$tmp" "$settings"
          rm -f "$tmp.base"
        ' "$HOME/.claude/settings.json"
      '';
    };
}
