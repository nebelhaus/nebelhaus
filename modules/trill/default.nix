# trill — the nebelhaus Messages client, shipped by default as a Homebrew cask
# from the family tap. Unlike the pounce daemon, trill is a normal windowed app,
# so it just rides den's Homebrew framework: declare the tap + cask and
# nix-darwin merges them into den's lists.
#
# Full Disk Access (trill reads ~/Library/Messages/chat.db, always read-only) is
# a one-time System Settings grant. Unlike an Accessibility grant keyed to a
# code signature, an FDA grant on an app at a stable /Applications path survives
# rebuilds — so trill needs none of pounce's self-signing dance.
{ config, lib, ... }:

lib.mkIf config.nebelhaus.trill.enable {
  homebrew.taps = [ "nebelhaus/tap" ];
  homebrew.casks = [ "trill" ];
}
