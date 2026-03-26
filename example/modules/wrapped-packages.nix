# Wrap home-manager programs as standalone packages.
#
# Each entry evaluates HM modules via wrapHomeModule, extracts config,
# and produces a wrapped derivation with bwrap on Linux.
{ inputs, config, ... }:
{
  imports = [ inputs.flake-parts.flakeModules.modules ];

  perSystem =
    { pkgs, lib, ... }:
    let
      wlib = inputs.hm-wrapper-modules.lib;
    in
    {
      packages = {

        # ── bat: auto-discovered mainPackage ──────────────────────────
        # programName = "bat" tells the adapter to find
        # programs.bat.package from the evaluated HM config.
        bat =
          let
            base = wlib.wrapHomeModule {
              inherit pkgs;
              programName = "bat";
              homeModules = [
                config.flake.modules.homeManager.bat
              ];
              home-manager = inputs.home-manager;
            };
          in
          base.wrap (
            { config, lib, ... }:
            {
              imports = [ wlib.modules.bwrapConfig ];
              bwrapConfig.binds.ro = wlib.mkBinds base.passthru.hmAdapter;
              # The adapter sets XDG_CONFIG_HOME to a store path as a
              # fallback for platforms without bwrap (e.g., macOS).
              # When bwrap is active, config files are bind-mounted to
              # their real paths, so the env override is redundant —
              # null it out to avoid confusing programs that inspect
              # XDG_CONFIG_HOME for other purposes.
              env.XDG_CONFIG_HOME = lib.mkIf config.bwrapConfig.enable (lib.mkForce null);
            }
          );

        # ── starship: explicit mainPackage ────────────────────────────
        # Pass the package directly instead of auto-discovery.
        # Useful when pname doesn't match the program name, or when
        # the package comes from a custom overlay or flake input.
        starship =
          let
            base = wlib.wrapHomeModule {
              inherit pkgs;
              mainPackage = pkgs.starship;
              homeModules = [
                config.flake.modules.homeManager.starship
              ];
              home-manager = inputs.home-manager;
            };
          in
          base.wrap (
            { config, lib, ... }:
            {
              imports = [ wlib.modules.bwrapConfig ];
              bwrapConfig.binds.ro = wlib.mkBinds base.passthru.hmAdapter;
              env.XDG_CONFIG_HOME = lib.mkIf config.bwrapConfig.enable (lib.mkForce null);
            }
          );

        # ── alacritty: composed with external HM modules ─────────────
        # homeModules is a list — compose any number of HM modules
        # from flake.modules.homeManager, external flake inputs, or
        # inline definitions. Here stylix theming (from stylix.nix)
        # auto-injects catppuccin-mocha colors, JetBrainsMono font,
        # and opacity into the generated alacritty.toml.
        alacritty =
          let
            base = wlib.wrapHomeModule {
              inherit pkgs;
              programName = "alacritty";
              homeModules = [
                config.flake.modules.homeManager.stylix
                config.flake.modules.homeManager.alacritty
              ];
              home-manager = inputs.home-manager;
            };
          in
          base.wrap (
            { config, lib, ... }:
            {
              imports = [ wlib.modules.bwrapConfig ];
              bwrapConfig.binds.ro = wlib.mkBinds base.passthru.hmAdapter;
              env.XDG_CONFIG_HOME = lib.mkIf config.bwrapConfig.enable (lib.mkForce null);
            }
          );

      };
    };
}
