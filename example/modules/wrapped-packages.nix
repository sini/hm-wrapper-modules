# Wrap home-manager programs as standalone `nix run`-able packages.
#
# Each entry evaluates an HM module, extracts its config, and produces
# a wrapped derivation. On Linux, bubblewrap presents the bundled config
# at the expected filesystem paths without modifying $HOME.
{ inputs, ... }:
{
  perSystem =
    { pkgs, ... }:
    let
      wlib = inputs.hm-wrapper-modules.lib;

      # Helper: wrap an HM module with bwrap on Linux, XDG fallback on darwin.
      mkWrapped =
        name: homeModules:
        let
          base = wlib.wrapHomeModule {
            inherit pkgs homeModules;
            programName = name;
            home-manager = inputs.home-manager;
          };
        in
        base.wrap (
          { config, lib, ... }:
          {
            imports = [ wlib.modules.bwrapConfig ];
            bwrapConfig.binds.ro = wlib.mkBinds base.passthru.hmAdapter;
            # Null out XDG_CONFIG_HOME when bwrap is active — bwrap presents
            # files at their real paths, so the env override is unnecessary.
            # On darwin, bwrap is a no-op and the adapter's mkDefault
            # XDG_CONFIG_HOME is the only way programs find their config.
            env.XDG_CONFIG_HOME = lib.mkIf config.bwrapConfig.enable (lib.mkForce null);
          }
        );
    in
    {
      packages = {

        # Tier 1: no context needed — static program config
        bat = mkWrapped "bat" [
          (
            { ... }:
            {
              programs.bat = {
                enable = true;
                config.theme = "ansi";
              };
            }
          )
        ];

        starship = mkWrapped "starship" [
          (
            { ... }:
            {
              programs.starship = {
                enable = true;
                settings = {
                  add_newline = false;
                  character.success_symbol = "[>](bold green)";
                  character.error_symbol = "[x](bold red)";
                };
              };
            }
          )
        ];

      };
    };
}
