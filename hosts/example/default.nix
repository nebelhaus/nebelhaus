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
  # The one personal bit the rice needs. Find your identity's SHA-1 with:
  #   security find-identity -v -p codesigning
  # Leave "" to run pounce unsigned (palette works; Accessibility features off).
  nebelhaus.pounce.signingIdentity = "";

  # Your apps — merged with the casks the modules install (ghostty, aerospace).
  homebrew.casks = [
    # "google-chrome"
    # "obsidian"
    # "slack"
    # "zen"
  ];

  # The shell/terminal layer (zsh aliases, starship, git identity, yazi, zellij,
  # ghostty theming) is yours to bring — drop it into home-manager here:
  #
  #   home-manager.users.${username} = {
  #     programs.git = {
  #       enable = true;
  #       userName = "Your Name";
  #       userEmail = "you@example.com";
  #     };
  #     # … starship, yazi, zellij, etc.
  #   };
  #
  # See the README's "Identity" section for the git-signing / GPG setup.
}
