# Wrapping Home-Manager Programs with hm-wrapper-modules

This example shows how to turn home-manager program configurations into
standalone `nix run`-able packages. Programs get their config bundled into
the derivation — no NixOS or home-manager activation required.

Two approaches are shown:
- **Raw API** (`wrapped-packages.nix`) — full control, inline calls
- **flakeModule** (`auto-wrapped-packages.nix`) — declarative, zero boilerplate

## Prerequisites

- Nix with flakes enabled
- A Linux system (bubblewrap is used for config presentation; macOS falls
  back to `XDG_CONFIG_HOME` override)

## Project structure

```
example/
├── flake.nix                          # flake-parts + import-tree
└── modules/
    ├── systems.nix                    # supported platforms
    ├── programs/
    │   ├── bat.nix                    # flake.modules.homeManager.bat
    │   ├── starship.nix               # flake.modules.homeManager.starship
    │   └── alacritty.nix              # flake.modules.homeManager.alacritty
    ├── stylix.nix                     # flake.modules.homeManager.stylix
    ├── wrapped-packages.nix           # Approach 1: raw API
    └── auto-wrapped-packages.nix      # Approach 2: flakeModule
```

This follows the [dendritic](https://github.com/mightyiam/dendritic) pattern:
`flake-parts` for modular outputs and `import-tree` to auto-import everything
in `modules/`. Each program is its own file declaring into the shared
`flake.modules.homeManager` namespace.

---

## Approach 1: Raw API (wrapped-packages.nix)

Full control over each wrapping call. Use this when you need per-program
customization or want to understand the mechanics.

### The wrapping pattern

Each program follows the same three-step pattern:

```nix
let
  wlib = inputs.hm-wrapper-modules.lib;
  base = wlib.wrapHomeModule {
    inherit pkgs;
    programName = "bat";
    homeModules = [ config.flake.modules.homeManager.bat ];
    home-manager = inputs.home-manager;
  };
in
base.wrap ({ config, lib, ... }: {
  imports = [ wlib.modules.bwrapConfig ];
  bwrapConfig.binds.ro = wlib.mkBinds base.passthru.hmAdapter;
  env.XDG_CONFIG_HOME = lib.mkIf config.bwrapConfig.enable (lib.mkForce null);
})
```

1. **`wrapHomeModule`** evaluates HM modules in a real home-manager context,
   extracts `home.packages`, `xdg.configFile`, `home.file`,
   `home.sessionVariables`, and activation scripts.

2. **`base.wrap`** extends the wrapper with bubblewrap. On Linux, `bwrapConfig`
   creates a mount namespace where bundled config files appear at their expected
   `$HOME` paths without modifying your real filesystem.

3. **`mkBinds`** generates the source-to-target bind mount mapping from the
   adapter's extracted file list.

The `XDG_CONFIG_HOME` line nulls the adapter's fallback env var when bwrap is
active — bwrap already presents files at the right paths, so the env override
is redundant. On macOS where bwrap is a no-op, the fallback still works.

### Call patterns

`wrapped-packages.nix` shows three variants:

**Auto-discovered package** — `programName` hints which `programs.*.package`
to use:

```nix
base = wlib.wrapHomeModule {
  inherit pkgs;
  programName = "bat";
  homeModules = [ config.flake.modules.homeManager.bat ];
  home-manager = inputs.home-manager;
};
```

**Explicit package** — when pname doesn't match or the package comes from a
custom input:

```nix
base = wlib.wrapHomeModule {
  inherit pkgs;
  mainPackage = pkgs.starship;
  homeModules = [ config.flake.modules.homeManager.starship ];
  home-manager = inputs.home-manager;
};
```

**Composed with external modules** — alacritty with stylix theming:

```nix
base = wlib.wrapHomeModule {
  inherit pkgs;
  programName = "alacritty";
  homeModules = [
    config.flake.modules.homeManager.stylix
    config.flake.modules.homeManager.alacritty
  ];
  home-manager = inputs.home-manager;
};
```

Stylix auto-injects catppuccin-mocha colors, JetBrainsMono font, and opacity
into the generated `alacritty.toml`.

---

## Approach 2: flakeModule (auto-wrapped-packages.nix)

Zero boilerplate. Import the flakeModule and declare what to wrap:

```nix
{ inputs, config, ... }:
{
  imports = [
    inputs.hm-wrapper-modules.flakeModules.default
    inputs.flake-parts.flakeModules.modules
  ];

  hmWrappers = {
    home-manager = inputs.home-manager;
    autoWrap = true;
    exclude = [ "stylix" ];
    baseModules = [ config.flake.modules.homeManager.stylix ];
  };
}
```

This auto-discovers every `flake.modules.homeManager` entry whose module args
only use standard HM args (`config`, `lib`, `pkgs`, etc.). Entries needing
custom context (e.g., a `user` arg) are skipped. Excluded names (like `stylix`)
are also skipped.

`baseModules` is prepended to every wrapped program — here stylix theming is
applied to all packages automatically.

### Explicit registration via flakeModule

You can also register programs explicitly instead of using auto-discovery:

```nix
hmWrappers = {
  home-manager = inputs.home-manager;
  programs.bat.homeModules = [ config.flake.modules.homeManager.bat ];
  programs.alacritty = {
    homeModules = [
      config.flake.modules.homeManager.stylix
      config.flake.modules.homeManager.alacritty
    ];
  };
  programs.gitkraken = {
    mainPackage = inputs.nixkraken.packages.${system}.gitkraken;
    homeModules = [ config.flake.modules.homeManager.gitkraken-config ];
  };
};
```

---

## Package auto-discovery

Both approaches support `mainPackage` auto-discovery. When omitted, the adapter
finds the main package by:

1. Checking `programs.<name>.package` (e.g., `programs.bat.package`)
2. Matching `home.packages` by pname or `meta.mainProgram`
3. Falling back to the first enabled program with a package

The `programName` parameter hints which program to look for.

## Run it

```bash
nix run .#bat
nix run .#starship
nix run .#alacritty
```

## How it works under the hood

The wrapper derivation output:

```
$out/
├── bin/bat                    # wrapper script
├── hm-xdg-config/            # extracted XDG config files
│   └── bat/
│       └── config
├── hm-home/                   # extracted home.file entries
└── share/, man/, ...          # symlinked from original package
```

The wrapper script:
1. Sets environment variables (session variables from HM, PATH for extra packages)
2. On Linux: execs via `bwrap --dev-bind / / --ro-bind $out/hm-xdg-config/bat ~/.config/bat ...`
3. On macOS: sets `XDG_CONFIG_HOME=$out/hm-xdg-config` and execs directly

Bubblewrap creates a mount namespace where the bundled config appears at
`~/.config/bat/config` while the rest of your filesystem (themes, fonts,
GTK config) remains visible through `--dev-bind / /`.

## Going further

- **Identity-dependent programs**: Pass user context via `extraSpecialArgs`
- **Activation scripts**: Set `runActivation = true` for programs needing
  runtime setup (e.g., GitKraken's `gk-configure`)
- **Read-write state**: Use `bwrapConfig.binds.rw` for directories the
  program needs to write to
- **Inspect extracted data**: Access `base.passthru.hmAdapter` for raw
  extracted packages, files, session variables, and activation scripts
