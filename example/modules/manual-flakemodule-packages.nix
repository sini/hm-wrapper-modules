# Manual wrapper registration via flakeModule.
#
# Same zero-boilerplate wrapping as auto-wrapped-packages.nix, but
# programs are listed explicitly via perSystem.hmWrappers.programs.
# Use this when you want to control exactly which programs are wrapped
# and how they're composed — including explicit mainPackage from pkgs.
#
# NOTE: Use one of wrapped-packages.nix (raw API),
# auto-wrapped-packages.nix (flakeModule + auto), or this file
# (flakeModule + manual). They all write to perSystem.packages.
{ inputs, config, ... }:
{
  imports = [
    inputs.hm-wrapper-modules.flakeModules.default
    inputs.flake-parts.flakeModules.modules
  ];

  # Flake-level config: home-manager input and shared settings
  hmWrappers = {
    home-manager = inputs.home-manager;
  };

  # perSystem: programs are declared here so mainPackage can use pkgs
  perSystem =
    { pkgs, ... }:
    {
      hmWrappers.programs = {

        # Simple: single HM module, package auto-discovered from programName
        bat.homeModules = [
          config.flake.modules.homeManager.bat
        ];

        # Explicit mainPackage: useful when pname doesn't match or the
        # package comes from a custom overlay or flake input
        starship = {
          mainPackage = pkgs.starship;
          homeModules = [
            config.flake.modules.homeManager.starship
          ];
        };

        # Composed: multiple HM modules with shared theming.
        # Stylix auto-injects catppuccin-mocha colors and JetBrainsMono
        # font into the generated alacritty.toml.
        alacritty.homeModules = [
          config.flake.modules.homeManager.stylix
          config.flake.modules.homeManager.alacritty
        ];

      };
    };
}
