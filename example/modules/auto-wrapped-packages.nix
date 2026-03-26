# Auto-wrapped packages via flakeModule.
#
# The flakeModule handles all wrapping boilerplate — wrapHomeModule,
# bwrap, mkBinds, XDG_CONFIG_HOME. Consumers just declare config.
#
# NOTE: This module and wrapped-packages.nix are alternative approaches.
# Use one or the other, not both (they both write to perSystem.packages).
{ inputs, config, ... }:
{
  imports = [
    inputs.hm-wrapper-modules.flakeModules.default
    inputs.flake-parts.flakeModules.modules
  ];

  hmWrappers = {
    home-manager = inputs.home-manager;

    # Auto-discover wrappable programs from flake.modules.homeManager.
    # Entries whose module args only use standard HM args (config, lib,
    # pkgs, etc.) become packages automatically.
    autoWrap = true;

    # Skip shared modules that aren't standalone programs.
    exclude = [ "stylix" ];

    # Stylix theming prepended to every wrapped program.
    baseModules = [ config.flake.modules.homeManager.stylix ];
  };
}
