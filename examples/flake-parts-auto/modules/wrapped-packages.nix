# Auto-wrapped packages via flakeModule.
#
# The flakeModule auto-discovers wrappable programs from
# flake.modules.homeManager and handles all wrapping boilerplate.
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
