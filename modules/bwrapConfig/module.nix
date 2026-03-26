{
  config,
  lib,
  wlib,
  pkgs,
  ...
}:
let
  cfg = config.bwrapConfig;
  isLinux = pkgs.stdenv.hostPlatform.isLinux;

  # Dereference symlinks in bind destinations at runtime. On HM-managed
  # systems, config files at $HOME paths are symlinks to the nix store.
  # bwrap can't create file-level bind mounts over symlinks, so we resolve
  # the destination to the real path, allowing bwrap to mount over it.
  # readlink -f runs fresh on each launch, so HM updates are picked up.
  resolveDest = target: "$(readlink -f \"$HOME\"/${lib.escapeShellArg target})";

  mkRoBind =
    src: "--ro-bind ${lib.escapeShellArg src} ${resolveDest cfg.binds.ro.${src}}";
  roBindArgs = lib.concatMapStringsSep " \\\n  " mkRoBind (lib.attrNames cfg.binds.ro);

  mkRwBind =
    src: "--bind ${lib.escapeShellArg src} ${resolveDest cfg.binds.rw.${src}}";
  rwBindArgs = lib.concatMapStringsSep " \\\n  " mkRwBind (lib.attrNames cfg.binds.rw);

  passthroughArgs = lib.optionalString cfg.passthrough.dev "--dev-bind / /";

  hasBinds = cfg.binds.ro != { } || cfg.binds.rw != { };
in
{
  options.bwrapConfig = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = isLinux;
      description = ''
        Enable bubblewrap filesystem overlay for presenting bundled config
        files at their expected paths. Automatically disabled on non-Linux
        platforms.
      '';
    };
    binds = {
      ro = lib.mkOption {
        type = lib.types.attrsOf lib.types.str;
        default = { };
        description = ''
          Read-only bind mounts. Keys are absolute store paths (sources),
          values are paths relative to `$HOME` (targets).
        '';
      };
      rw = lib.mkOption {
        type = lib.types.attrsOf lib.types.str;
        default = { };
        description = ''
          Read-write bind mounts. Keys are absolute paths (sources),
          values are paths relative to `$HOME` (targets).
          Used for program state directories that need mutation.
        '';
      };
    };
    passthrough = {
      dev = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = ''
          Pass through the entire filesystem via `--dev-bind / /`.
          This makes bwrap a presentation layer, not a security sandbox.
          Bind mounts overlay specific paths on top of the full filesystem.
        '';
      };
    };
  };

  config = lib.mkMerge [
    (lib.mkIf (cfg.enable && hasBinds) {
      argv0type =
        command:
        "exec ${pkgs.bubblewrap}/bin/bwrap ${passthroughArgs} ${roBindArgs} ${rwBindArgs} ${command}";
    })
    {
      meta.maintainers = [ wlib.maintainers.birdee ];
      meta.description = ''
        Bubblewrap filesystem overlay module.

        Presents store-path config files at their expected filesystem locations
        using Linux mount namespaces. Programs see their config at normal paths
        (e.g., `~/.config/bat/config`) without modifying the real filesystem.

        Linux only. On darwin this module is a no-op.

        ---
      '';
    }
  ];
}
