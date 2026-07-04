{
  description = "nebelhaus — an opinionated macOS, raised in the fog";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

    nix-darwin = {
      url = "github:LnL7/nix-darwin/master";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    catppuccin.url = "github:catppuccin/nix";

    # The silver-mist theme (Catppuccin Mocha, whiskered). Rendered in a pure
    # derivation so themes rebuild with `darwin-rebuild`.
    nebelung = {
      url = "github:nebelhaus/nebelung";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.catppuccin.follows = "catppuccin";
    };

    # The command palette. Its overlay puts `pounce` + `pounce-commands` in pkgs.
    # pounce bakes the nebelung palette into its binary at build time; point it at
    # the rice's own nebelung so the app can't drift from the rest of the theme.
    pounce = {
      url = "github:nebelhaus/pounce";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.nebelung.follows = "nebelung";
    };

    nix-index-database = {
      url = "github:nix-community/nix-index-database";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    inputs@{
      self,
      nixpkgs,
      nix-darwin,
      home-manager,
      catppuccin,
      nebelung,
      pounce,
      nix-index-database,
    }:
    let
      # The house builder. Point it at a host file and it raises a full system.
      #   mkNebelhaus { username = "ada"; hostname = "lovelace"; host = ./hosts/ada; }
      mkNebelhaus =
        {
          username,
          hostname,
          host ? ./hosts/example,
          system ? "aarch64-darwin",
          extraModules ? [ ],
        }:
        nix-darwin.lib.darwinSystem {
          inherit system;
          specialArgs = { inherit inputs username hostname; };
          modules = [
            { nixpkgs.overlays = [ pounce.overlays.default ]; }
            home-manager.darwinModules.home-manager
            {
              users.users.${username} = {
                name = username;
                home = "/Users/${username}";
              };
              home-manager.useGlobalPkgs = true;
              home-manager.useUserPackages = true;
              home-manager.backupFileExtension = "backup";
              home-manager.extraSpecialArgs = {
                inherit username inputs;
                nebelung = {
                  themes = nebelung.packages.${system}.default;
                  palette = nebelung.palette;
                };
              };
              home-manager.sharedModules = [
                catppuccin.homeModules.catppuccin
                nix-index-database.homeModules.nix-index
              ];
            }
            self.darwinModules.default
            host
          ]
          ++ extraModules;
        };
    in
    {
      # Import the whole house, or cherry-pick a room. Each is a nix-darwin module.
      darwinModules = {
        den = ./modules/den;
        hearth = ./modules/hearth;
        prowl = ./modules/prowl;
        sill = ./modules/sill;
        collar = ./modules/collar;
        pounce = ./modules/pounce;
        default = ./modules;
      };

      inherit mkNebelhaus;

      # `nix run github:nebelhaus/nebelhaus#pounce`
      packages.aarch64-darwin.pounce = pounce.packages.aarch64-darwin.default;

      # `nix run github:nebelhaus/nebelhaus#bootstrap` — raise the house on a
      # fresh Mac. Scaffolds a thin personal config at ~/.config/nix; it never
      # touches this repo. Same script as the curl|bash path (bootstrap.sh).
      apps = nixpkgs.lib.genAttrs [ "aarch64-darwin" "x86_64-darwin" ] (system: {
        bootstrap = {
          type = "app";
          program = "${
            nixpkgs.legacyPackages.${system}.writeShellScriptBin "nebelhaus-bootstrap" (
              builtins.readFile ./bootstrap.sh
            )
          }/bin/nebelhaus-bootstrap";
        };
      });

      # `nix fmt` — nixfmt, the house style.
      formatter = nixpkgs.lib.genAttrs [ "aarch64-darwin" "x86_64-darwin" ] (
        system: nixpkgs.legacyPackages.${system}.nixfmt
      );

      # The template others copy. Build with:
      #   nix build .#darwinConfigurations.example.system
      darwinConfigurations.example = mkNebelhaus {
        username = "you";
        hostname = "example";
      };
    };
}
