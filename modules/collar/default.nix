# Collar — the tag your machine wears. Identity & auth done the sane way.
#
# Touch ID for sudo, with `reattach` — REQUIRED if you ever run sudo inside a
# terminal multiplexer (tmux/zellij/screen). A multiplexer detaches the process
# from the GUI (Aqua) session, so pam_tid.so can't reach the Touch ID UI and the
# prompt beachballs. pam_reattach.so (inserted before pam_tid) reattaches auth to
# the GUI session and fixes the hang. Falls back to the password prompt if Touch
# ID is cancelled.
#
# YubiKey / GPG: this rice signs git commits with a GPG key (yours), but the key
# material and smartcard/YubiKey setup live outside Nix — see the README's
# "Identity" section for the one-time gpg-agent + pinentry-mac steps.
{ ... }:

{
  security.pam.services.sudo_local.touchIdAuth = true;
  security.pam.services.sudo_local.reattach = true;
}
