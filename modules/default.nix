# The whole house. Import this for the full rice, or import individual rooms
# (den / prowl / sill / collar / pounce) from `darwinModules` in the flake.
{
  imports = [
    ./options.nix
    ./den
    ./hearth
    ./prowl
    ./sill
    ./collar
    ./pounce
  ];
}
