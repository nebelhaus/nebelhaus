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
