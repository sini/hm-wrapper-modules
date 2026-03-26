# hm-wrapper-modules

Home-manager module adapter for [nix-wrapper-modules](https://github.com/BirdeeHub/nix-wrapper-modules).

Evaluates arbitrary home-manager modules in a real HM context, extracts their
side effects (packages, files, activation scripts, session variables), and
produces portable wrapped package derivations via nix-wrapper-modules.

On Linux, bubblewrap presents bundled config at expected filesystem paths
without modifying `$HOME`. On macOS, `XDG_CONFIG_HOME` falls back to the
store path.

## Quick start with flake-parts

The easiest way to use hm-wrapper-modules is via the flake-parts module.
Declare your home-manager programs as `flake.modules.homeManager` entries
(following the [dendritic](https://github.com/mightyiam/dendritic) pattern),
then register them for wrapping:

```nix
# flake.nix
{
  inputs = {
    flake-parts.url = "github:hercules-ci/flake-parts";
    import-tree.url = "github:vic/import-tree";
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    home-manager.url = "github:nix-community/home-manager";
    hm-wrapper-modules.url = "github:sini/hm-wrapper-modules";
    hm-wrapper-modules.inputs.nixpkgs.follows = "nixpkgs";
    hm-wrapper-modules.inputs.home-manager.follows = "home-manager";
  };

  outputs = inputs:
    inputs.flake-parts.lib.mkFlake { inherit inputs; } (inputs.import-tree ./modules);
}
```

```nix
# modules/programs/bat.nix
{
  flake.modules.homeManager.bat = { ... }: {
    programs.bat = {
      enable = true;
      config.theme = "ansi";
    };
  };
}
```

### Manual registration

List programs explicitly in `perSystem.hmWrappers.programs`. This gives
you access to `pkgs` for explicit `mainPackage` references:

```nix
# modules/wrapped-packages.nix
{ inputs, config, ... }:
{
  imports = [
    inputs.hm-wrapper-modules.flakeModules.default
    inputs.flake-parts.flakeModules.modules
  ];

  hmWrappers.home-manager = inputs.home-manager;

  perSystem = { pkgs, ... }: {
    hmWrappers.programs = {
      bat.homeModules = [ config.flake.modules.homeManager.bat ];

      starship = {
        mainPackage = pkgs.starship;
        homeModules = [ config.flake.modules.homeManager.starship ];
      };

      # Compose multiple HM modules — stylix auto-themes alacritty
      alacritty.homeModules = [
        config.flake.modules.homeManager.stylix
        config.flake.modules.homeManager.alacritty
      ];
    };
  };
}
```

### Auto-discovery

Automatically wrap all `flake.modules.homeManager` entries whose module
args only use standard HM args (`config`, `lib`, `pkgs`, etc.):

```nix
# modules/wrapped-packages.nix
{ inputs, config, ... }:
{
  imports = [
    inputs.hm-wrapper-modules.flakeModules.default
    inputs.flake-parts.flakeModules.modules
  ];

  hmWrappers = {
    home-manager = inputs.home-manager;
    autoWrap = true;
    exclude = [ "stylix" ];  # skip non-program entries
    baseModules = [ config.flake.modules.homeManager.stylix ];
  };
}
```

### flakeModule options

**Flake-level** (system-independent):

| Option | Type | Default | Description |
|---|---|---|---|
| `hmWrappers.home-manager` | raw | required | HM flake input |
| `hmWrappers.baseModules` | listOf raw | `[]` | Prepended to every program's homeModules |
| `hmWrappers.autoWrap` | bool | `false` | Auto-discover from `flake.modules.homeManager` |
| `hmWrappers.exclude` | listOf str | `[]` | Skip during auto-discovery |
| `hmWrappers.stateVersion` | str | `"26.05"` | HM stateVersion |
| `hmWrappers.extraSpecialArgs` | attrsOf raw | `{}` | Extra args for HM evaluation |

**perSystem** (has access to `pkgs`):

| Option | Type | Default | Description |
|---|---|---|---|
| `hmWrappers.programs.<name>.homeModules` | listOf raw | required | HM modules for this program |
| `hmWrappers.programs.<name>.mainPackage` | package | null | Explicit package (auto-discovered if null) |

## Direct API

For full control without the flake-parts module, use the library functions
directly:

```nix
let
  wlib = inputs.hm-wrapper-modules.lib;

  base = wlib.wrapHomeModule {
    inherit pkgs;
    programName = "bat";
    homeModules = [({ ... }: { programs.bat.enable = true; })];
    home-manager = inputs.home-manager;
  };
in
base.wrap ({ config, lib, ... }: {
  imports = [ wlib.modules.bwrapConfig ];
  bwrapConfig.binds.ro = wlib.mkBinds base.passthru.hmAdapter;
  env.XDG_CONFIG_HOME = lib.mkIf config.bwrapConfig.enable (lib.mkForce null);
})
```

### `wrapHomeModule` API

```nix
wlib.wrapHomeModule {
  pkgs;                               # nixpkgs instance
  home-manager;                       # HM flake input
  homeModules;                        # list of HM modules
  mainPackage ? null;                 # auto-discovered if omitted
  programName ? null;                 # hint for auto-discovery
  extraSpecialArgs ? {};
  stateVersion ? "26.05";
  extractPackages ? true;
  extractFiles ? true;
  extractSessionVariables ? true;
  runActivation ? false;              # wire activation scripts into runShell
}
```

Returns a wrapper-module `.config` with `.wrap`/`.apply`/`.eval`/`.wrapper`.

### `mainPackage` auto-discovery

When `mainPackage` is omitted, discovered via:
1. `programs.<programName>.package` (if hint given)
2. `home.packages` matched by pname/mainProgram/name prefix
3. First enabled program with a package (via `tryEval`)

Baseline diff filters HM-internal packages from candidates.

### `mkBinds`

Maps adapter passthru to `bwrapConfig.binds.ro` entries. Uses
`placeholder "out"` for source paths (attrset keys strip string context).

## What it does

### Extraction layer (`wrapHomeModule`)

Evaluates HM modules via `homeManagerConfiguration`, then maps their outputs
to wrapper-module primitives:

| HM output | Wrapper equivalent |
|---|---|
| `home.packages` | `extraPackages` |
| `home.file` (text) | `constructFiles` |
| `home.file` (source) | `buildCommand` + `drv` attrs |
| `xdg.configFile` | files in `$out/hm-xdg-config/` + `XDG_CONFIG_HOME` env |
| `home.sessionVariables` | `env` (with `mkDefault`, coerced to strings) |
| `home.activation` | `passthru.hmAdapter.activationScripts` |

HM-internal files are filtered via baseline diff (empty HM evaluation).

### Presentation layer (`bwrapConfig`)

Standalone wrapper module using bubblewrap to present store-path config files
at their expected filesystem locations via Linux mount namespaces. Programs see
their config at normal paths (e.g., `~/.config/bat/config`) without modifying
the real filesystem. Bind targets are resolved at runtime via `readlink -f`
(bwrap can't mount over symlinks). Darwin is a no-op (TODO).

## Flake outputs

| Output | Description |
|---|---|
| `lib.wrapHomeModule` | HM adapter function |
| `lib.mkBinds` | Adapter passthru to bwrap binds |
| `lib.*` | Full nix-wrapper-modules API (re-exported) |
| `modules.bwrapConfig` | Bwrap presentation module path |
| `flakeModules.default` | Flake-parts module with `hmWrappers` options |
| `checks.<system>.*` | Test suite |

## Examples

See [`examples/`](examples/) for three complete example flakes:

- **`direct/`** — inline `wrapHomeModule` + bwrap calls, full control
- **`flake-parts-manual/`** — flakeModule with explicit `perSystem.hmWrappers.programs`
- **`flake-parts-auto/`** — flakeModule with `autoWrap` from `flake.modules.homeManager`

All three produce the same packages from identical HM module declarations.

## Running tests

```bash
nix flake check -Lv
```
