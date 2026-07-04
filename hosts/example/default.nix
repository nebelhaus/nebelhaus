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

  # pounce signing. Find your identity's SHA-1 with:
  #   security find-identity -v -p codesigning
  # Leave "" to run pounce unsigned (palette works; Accessibility features off).
  nebelhaus.pounce.signingIdentity = "";

  # Optional: shortlist for the Super-Shift-t "new tab" picker — it opens on
  # just these home-relative dirs instead of all of $HOME. Unset = browse $HOME.
  nebelhaus.hearth.newTabDirs = [
    # "code"
    # ".config"
  ];

  # Your apps — merged with the casks the modules install (ghostty, aerospace).
  homebrew.casks = [
    # "google-chrome"
    # "obsidian"
    # "slack"
    # "zen"
  ];

  # The shell/terminal layer ships in the `hearth` module (zsh, starship, git,
  # yazi, zellij, ghostty — all Nebelung-themed). To add YOUR personal bits on
  # top (extra packages, secret env vars, private aliases), extend home-manager:
  #
  #   home-manager.users.${username} = {
  #     home.packages = with pkgs; [ /* your tools */ ];
  #     programs.zsh.initContent = lib.mkAfter ''
  #       export SOME_API_KEY="$(cat ~/.secrets/some-key)"
  #     '';
  #   };
}
