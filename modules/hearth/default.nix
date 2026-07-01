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
        userName = gitCfg.name;
        userEmail = gitCfg.email;
        signing = lib.mkIf (gitCfg.signingKey != "") {
          key = gitCfg.signingKey;
          signByDefault = true;
        };
        extraConfig = {
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
        };
      };

      programs.lazygit.enable = true;

      programs.lsd.enable = true;
      programs.lsd.enableZshIntegration = false;

      programs.bat = {
        enable = true;
        config = {
          style = "header,grid";
          tabs = "2";
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
          # crashes on yazi 26.x. This copy ports it to the current API.
          glow = ./yazi/plugins/glow.yazi;
          piper = pkgs.yaziPlugins.piper;
        };
        keymap.mgr.prepend_keymap = [
          {
            on = "<Esc>";
            run = "quit";
            desc = "Close the peek browser";
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
              run = ''glow -p "$@"'';
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

      programs.fzf = {
        enable = true;
        enableZshIntegration = true;
      };

      programs.zellij.enable = true;

      # Catppuccin: `catppuccin.flavor` is the single source of truth — every
      # integration follows it. Raw dotfiles nix can't inject into (ghostty
      # config, zellij config.kdl) name the flavor manually; keep them in sync.
      catppuccin.autoEnable = true;
      catppuccin.enable = true;
      catppuccin.flavor = "mocha";
      catppuccin.bat.enable = true;
      catppuccin.starship.enable = false; # starship uses the Nebelung palette above
      catppuccin.delta.enable = true;
      catppuccin.fzf.enable = true;
      catppuccin.lazygit.enable = true;
      catppuccin.lsd.enable = true;
      catppuccin.zellij.enable = false; # managed as a raw dotfile below

      programs.nix-index = {
        enable = true;
        enableZshIntegration = true;
      };
      programs.nix-index-database.comma.enable = true;

      programs.home-manager.enable = true;

      # ---- dotfiles + Nebelung theme drops ----
      home.file = {
        # ghostty (config lives in Application Support; theme lookup is XDG)
        "Library/Application Support/com.mitchellh.ghostty/config".source = ./ghostty/config;
        ".config/ghostty/themes/nebelung".source =
          "${nebelung.themes}/ghostty/themes/catppuccin-mocha.conf";

        # zellij
        ".config/zellij/config.kdl".source = ./zellij/config.kdl;
        ".config/zellij/themes/nebelung.kdl".source =
          "${nebelung.themes}/zellij/themes/nebelung.kdl";
        ".config/zellij/layouts" = {
          source = ./zellij/layouts;
          recursive = true;
        };
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
    };
}
