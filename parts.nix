{ wlib }:
{
  config,
  lib,
  flake-parts-lib,
  ...
}:
let
  inherit (lib) types mkOption;
  file = ./parts.nix;
  topConfig = config;
  cfg = config.hmWrappers;

  standardHmArgs = [
    "config"
    "lib"
    "pkgs"
    "modulesPath"
    "options"
    "osConfig"
    "nixosConfig"
    "inputs"
    "..."
  ];

  getModuleArgs =
    mod:
    if lib.isFunction mod then
      lib.attrNames (builtins.functionArgs mod)
    else if lib.isAttrs mod && mod ? __functor then
      lib.attrNames (builtins.functionArgs (mod.__functor mod))
    else
      [ ];

  isWrappable =
    mod:
    let
      args = getModuleArgs mod;
    in
    args == [ ] || lib.all (a: lib.elem a standardHmArgs) args;

  programSubmodule = types.submodule {
    options = {
      mainPackage = mkOption {
        type = types.nullOr types.package;
        default = null;
        description = ''
          Explicit main package to wrap. When null, auto-discovered from the
          home-manager module evaluation via the attribute name as programName.
        '';
      };
      homeModules = mkOption {
        type = types.listOf types.raw;
        description = ''
          List of home-manager modules to evaluate for this program.
        '';
      };
    };
  };
in
{
  _file = file;
  key = file;

  # ── Flake-level options (system-independent) ──────────────────────
  options.hmWrappers = {
    home-manager = mkOption {
      type = types.raw;
      description = ''
        The home-manager flake input. Required for evaluating HM modules.
      '';
    };

    baseModules = mkOption {
      type = types.listOf types.raw;
      default = [ ];
      description = ''
        Home-manager modules prepended to every program's module list.
        Useful for shared configuration like stylix theming.
      '';
    };

    autoWrap = mkOption {
      type = types.bool;
      default = false;
      description = ''
        Automatically populate `perSystem.hmWrappers.programs` from
        `flake.modules.homeManager`. Each wrappable module becomes a program
        entry with its single module as `homeModules`.
      '';
    };

    exclude = mkOption {
      type = types.listOf types.str;
      default = [ ];
      description = ''
        Module names to skip during auto-discovery when `autoWrap` is enabled.
      '';
    };

    stateVersion = mkOption {
      type = types.str;
      default = "26.05";
      description = ''
        The home-manager `stateVersion` used for all adapter evaluations.
      '';
    };

    extraSpecialArgs = mkOption {
      type = types.attrsOf types.raw;
      default = { };
      description = ''
        Extra `specialArgs` passed to every home-manager evaluation.
      '';
    };
  };

  # ── perSystem: programs option + package generation ───────────────
  options.perSystem = flake-parts-lib.mkPerSystemOption (
    {
      config,
      pkgs,
      lib,
      ...
    }:
    let
      psCfg = config.hmWrappers;
    in
    {
      options.hmWrappers.programs = mkOption {
        type = types.attrsOf programSubmodule;
        default = { };
        description = ''
          Programs to wrap via the home-manager adapter. Each entry produces
          a package in `perSystem.packages`. Defined at perSystem level so
          `mainPackage` can reference `pkgs`.
        '';
      };

      # Auto-discovery: populate programs from flake.modules.homeManager.
      # Uses top-level `cfg` (from outer scope) for autoWrap/exclude,
      # and top-level `config` (renamed below) for flake.modules.
      config.hmWrappers.programs =
        let
          hm = topConfig.flake.modules.homeManager or { };
          filtered = lib.filterAttrs (name: mod: !(lib.elem name cfg.exclude) && isWrappable mod) hm;
        in
        lib.mkIf cfg.autoWrap (builtins.mapAttrs (_name: mod: { homeModules = [ mod ]; }) filtered);

      # Generate packages from programs
      config.packages = builtins.mapAttrs (
        name: programCfg:
        let
          base = wlib.wrapHomeModule (
            {
              inherit pkgs;
              homeModules = cfg.baseModules ++ programCfg.homeModules;
              home-manager = cfg.home-manager;
              stateVersion = cfg.stateVersion;
              extraSpecialArgs = cfg.extraSpecialArgs;
            }
            // lib.optionalAttrs (programCfg.mainPackage != null) {
              mainPackage = programCfg.mainPackage;
            }
            // lib.optionalAttrs (programCfg.mainPackage == null) {
              programName = name;
            }
          );
        in
        base.wrap (
          {
            config,
            lib,
            ...
          }:
          {
            imports = [ wlib.modules.bwrapConfig ];
            bwrapConfig.binds.ro = wlib.mkBinds base.passthru.hmAdapter;
            env.XDG_CONFIG_HOME = lib.mkIf config.bwrapConfig.enable (lib.mkForce null);
          }
        )
      ) psCfg.programs;
    }
  );
}
