# Host-provided identity. These are the values that are personal to YOU rather
# than part of the rice — a host file (see hosts/example) sets them.
{ lib, ... }:

{
  options.nebelhaus = {
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
