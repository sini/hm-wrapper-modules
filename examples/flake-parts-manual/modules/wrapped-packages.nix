# Manual wrapper registration via flakeModule.
#
# Programs are listed explicitly via perSystem.hmWrappers.programs.
# The flakeModule handles all wrapping boilerplate — wrapHomeModule,
# bwrap, mkBinds, XDG_CONFIG_HOME.
{ inputs, config, ... }:
{
  imports = [
    inputs.hm-wrapper-modules.flakeModules.default
    inputs.flake-parts.flakeModules.modules
  ];

  hmWrappers = {
    home-manager = inputs.home-manager;
  };

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
