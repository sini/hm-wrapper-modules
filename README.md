# hm-wrapper-modules

Home-manager module adapter for [nix-wrapper-modules](https://github.com/BirdeeHub/nix-wrapper-modules).

Evaluates arbitrary home-manager modules in a real HM context, extracts their
side effects (packages, files, activation scripts, session variables), and
produces portable wrapped package derivations via nix-wrapper-modules.

## Quick start

```nix
# flake.nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    hm-wrapper-modules.url = "github:sini/hm-wrapper-modules";
    hm-wrapper-modules.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = { nixpkgs, hm-wrapper-modules, ... }:
  let
    pkgs = import nixpkgs { system = "x86_64-linux"; };
    wlib = hm-wrapper-modules.lib;
  in {
    packages.x86_64-linux.bat = let
      wrapped = wlib.wrapHomeModule {
        inherit pkgs;
        home-manager = hm-wrapper-modules.inputs.home-manager;
        homeModules = [
          ({ ... }: {
            programs.bat.enable = true;
            programs.bat.config.theme = "catppuccin-mocha";
          })
        ];
      };
    in wrapped.wrap {
      imports = [ wlib.modules.bwrapConfig ];
      bwrapConfig.binds.ro = wlib.mkBinds wrapped.passthru.hmAdapter;
    };
  };
}
```

```bash
nix run .#bat -- --list-themes
```

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
| `home.sessionVariables` | `env` (with `mkDefault`) |
| `home.activation` | `passthru.hmAdapter.activationScripts` |

HM-internal files are filtered via baseline diff (empty HM evaluation).

### Presentation layer (`bwrapConfig`)

Standalone wrapper module that uses bubblewrap to present store-path config
files at their expected filesystem locations via Linux mount namespaces.
Programs see their config at normal paths (e.g., `~/.config/bat/config`)
without modifying the real filesystem. Darwin is a no-op (TODO).

## API

```nix
wlib.wrapHomeModule {
  pkgs;                               # nixpkgs instance
  home-manager;                       # HM flake input
  homeModules;                        # list of HM modules
  mainPackage ? null;                 # auto-discovered if omitted
  programName ? null;                 # hint for auto-discovery
  extraSpecialArgs ? {};              # extra args for HM evaluation
  stateVersion ? "24.11";
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

### `mkBinds`

Maps adapter passthru to `bwrapConfig.binds.ro` entries:

```nix
wrapped.wrap {
  imports = [ wlib.modules.bwrapConfig ];
  bwrapConfig.binds.ro = wlib.mkBinds wrapped.passthru.hmAdapter;
}
```

## Flake outputs

| Output | Description |
|---|---|
| `lib.wrapHomeModule` | HM adapter function |
| `lib.mkBinds` | Adapter passthru to bwrap binds |
| `lib.*` | Full nix-wrapper-modules API (re-exported) |
| `modules.bwrapConfig` | Bwrap presentation module path |
| `checks.<system>.*` | Test suite |

## Running tests

```bash
nix flake check -Lv
```
