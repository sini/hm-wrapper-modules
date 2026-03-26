{
  description = "Home-manager module adapter for nix-wrapper-modules";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    nix-wrapper-modules.url = "github:BirdeeHub/nix-wrapper-modules";
    nix-wrapper-modules.inputs.nixpkgs.follows = "nixpkgs";
    home-manager.url = "github:nix-community/home-manager";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs =
    {
      self,
      nixpkgs,
      nix-wrapper-modules,
      home-manager,
    }:
    let
      inherit (nixpkgs) lib;
      wlib = nix-wrapper-modules.lib;
      forAllSystems = lib.genAttrs lib.platforms.all;

      hmAdapter = import ./lib/hm-adapter.nix { inherit lib wlib; };

      # Extend upstream wlib with our adapter functions and bwrapConfig module.
      # Consumers get the full nix-wrapper-modules API plus HM adapter in one import.
      extendedWlib = wlib // {
        inherit (hmAdapter) wrapHomeModule mkBinds;
        modules = wlib.modules // {
          bwrapConfig = ./modules/bwrapConfig/module.nix;
        };
      };
    in
    {
      lib = extendedWlib;

      flakeModules.default = import ./parts.nix { wlib = extendedWlib; };

      modules = {
        bwrapConfig = ./modules/bwrapConfig/module.nix;
      };

      checks = forAllSystems (
        system:
        let
          pkgs = import nixpkgs {
            inherit system;
            config.allowUnfree = true;
          };

          checkFiles = builtins.readDir ./checks;
          importCheck =
            name:
            let
              fn = import (./checks + "/${name}");
              fargs = builtins.functionArgs fn;
              args = {
                inherit pkgs;
                self = self;
              }
              // lib.optionalAttrs (fargs ? home-manager) { inherit home-manager; };
            in
            {
              name = lib.removeSuffix ".nix" name;
              value = fn args;
            };
        in
        builtins.listToAttrs (
          map importCheck (builtins.filter (name: lib.hasSuffix ".nix" name) (builtins.attrNames checkFiles))
        )
      );

      formatter = forAllSystems (system: nixpkgs.legacyPackages.${system}.nixfmt-rfc-style);
    };
}
