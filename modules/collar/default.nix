# Collar — the tag your machine wears. Identity & auth done the sane way.
#
# Touch ID for sudo, with `reattach` — REQUIRED if you ever run sudo inside a
# terminal multiplexer (tmux/zellij/screen). A multiplexer detaches the process
# from the GUI (Aqua) session, so pam_tid.so can't reach the Touch ID UI and the
# prompt beachballs. pam_reattach.so (inserted before pam_tid) reattaches auth to
# the GUI session and fixes the hang. Falls back to the password prompt if Touch
# ID is cancelled.
#
# Passwordless `darwin-rebuild switch` — activating a build is the one privileged
# thing this rice does constantly, and a Touch-ID prompt per rebuild is friction
# with no security win (you already authed to *build* it). The NOPASSWD rule
# below exempts it. Two gotchas make this fragile if written the obvious way:
#   1. Match the STABLE path, not the store path. sudo ≥1.9.17 (shipped with
#      macOS 26.6) stopped dereferencing the command's symlink before matching
#      sudoers — so a rule on `/nix/store/*-darwin-rebuild/…` only matches if you
#      type that literal store path, which nobody does. Every real invocation
#      goes through `/run/current-system/sw/bin/darwin-rebuild` (bench + haus
#      route their `switch` there for exactly this reason), so that's the target.
#   2. nix-darwin's environment.etc is symlink-only, so the rule lands as a 0444
#      store symlink. sudo loads it fine — it refuses only group/world-WRITABLE
#      sudoers files, not merely readable ones (nix-darwin's own extra-config is
#      0444 too). `visudo -c` may cosmetically warn "should be 0440"; harmless.
#
# YubiKey / GPG: this rice signs git commits with a GPG key (yours), but the key
# material and smartcard/YubiKey setup live outside Nix — see the README's
# "Identity" section for the one-time gpg-agent + pinentry-mac steps.
{ username, ... }:

{
  security.pam.services.sudo_local.touchIdAuth = true;
  security.pam.services.sudo_local.reattach = true;

  environment.etc."sudoers.d/darwin-rebuild".text = ''
    ${username} ALL=(ALL) NOPASSWD: /run/current-system/sw/bin/darwin-rebuild
  '';
}
