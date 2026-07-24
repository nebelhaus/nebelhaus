# Your machine. Copy this to hosts/<hostname>/ and make it yours, then wire it
# up in flake.nix:
#
#   darwinConfigurations.<hostname> = mkNebelhaus {
#     username = "you";
#     hostname = "<hostname>";
#     host = ./hosts/<hostname>;
#   };
#
# This is a plain nix-darwin module — anything nix-darwin or home-manager
# accepts goes here, and it merges with what the rice modules already declare.
{ username, ... }:

{
  # ---- your identity ----
  nebelhaus.git.name = "Your Name";
  nebelhaus.git.email = "you@example.com";
  # GPG key id for commit signing; leave "" to disable signing.
  nebelhaus.git.signingKey = "";
  # Hearth ships a compact, framework-independent set of Git shell aliases
  # (gst, gco, gp, grbi, gwt, …). Extend/override them here, or set one to null
  # to remove it:
  # nebelhaus.git.shellAliases = {
  #   gst = "git status --short --branch";
  #   gsync = "git pull --rebase --autostash";
  #   gco = null;
  # };

  # pounce signing. Find your identity's SHA-1 with:
  #   security find-identity -v -p codesigning
  # Leave "" to run pounce unsigned (palette works; Accessibility features off).
  nebelhaus.pounce.signingIdentity = "";

  # Where secretspec finds secret VALUES on this machine. Default "keyring" is
  # the local macOS keychain (no accounts, values re-entered once per Mac —
  # `secretspec check` lists what's missing). A cloud provider ("gcsm",
  # "awssm", "bws", "onepassword", …) makes values follow you to the next Mac;
  # you configure its credentials outside Nix. WHICH secrets exist is each
  # project's committed secretspec.toml, not an option here.
  # nebelhaus.secrets.provider = "keyring";

  # Text expansion (espanso): type a trigger, get the expansion, in any app —
  # terminal included. Opt-in: installs the Espanso.app cask and needs a
  # one-time Accessibility grant the first time it runs (System Settings →
  # Privacy & Security → Accessibility → enable Espanso). Grant survives reboots
  # + updates because it runs the signed app bundle, not a nix-store binary.
  # nebelhaus.snippets = {
  #   enable = true;
  #   matches = [
  #     { trigger = "@@"; replace = "you@example.com"; }
  #   ];
  # };

  # Obsidian keeps appearance per vault. List home-relative vault paths here to
  # install/select the full Nebelung theme on every rebuild; empty leaves all
  # vaults untouched. The vault must already contain a .obsidian directory.
  # nebelhaus.hearth.obsidianVaults = [
  #   "Library/Mobile Documents/iCloud~md~obsidian/Documents/notes"
  # ];

  # Your apps — merged with the casks the modules install (ghostty, aerospace).
  homebrew.casks = [
    # "google-chrome"
    # "obsidian"
    # "slack"
    # "zen"
  ];

  # The shell/terminal layer ships in the `hearth` module (zsh, starship, git,
  # yazi, zellij, ghostty — all Nebelung-themed). To add YOUR personal bits on
  # top (extra packages, private aliases, the rare env var every shell needs),
  # extend home-manager — per-project secrets belong in secretspec instead:
  #
  #   home-manager.users.${username} = {
  #     home.packages = with pkgs; [ /* your tools */ ];
  #     programs.zsh.initContent = lib.mkAfter ''
  #       alias deploy="ssh you@yourserver"
  #     '';
  #   };
}
