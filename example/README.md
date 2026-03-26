# Wrapping Home-Manager Programs with hm-wrapper-modules

This example shows how to turn home-manager program configurations into
standalone `nix run`-able packages. Programs get their config bundled into
the derivation — no NixOS or home-manager activation required.

## Prerequisites

- Nix with flakes enabled
- A Linux system (bubblewrap is used for config presentation; macOS falls
  back to `XDG_CONFIG_HOME` override)

## Project structure

```
example/
├── flake.nix                      # flake-parts + import-tree
└── modules/
    ├── systems.nix                # supported platforms
    ├── wrapped-packages.nix       # wrapped programs (bat, starship, alacritty)
    └── devshell.nix               # dev shell with all wrapped packages
```

This follows the [dendritic](https://github.com/mightyiam/dendritic) pattern:
`flake-parts` for modular outputs and `import-tree` to auto-import everything
in `modules/`.

## Step 1: Understand the flake inputs

Open `flake.nix`. The key inputs are:

```nix
hm-wrapper-modules.url = "github:sini/hm-wrapper-modules";
home-manager.url = "github:nix-community/home-manager";
stylix.url = "github:nix-community/stylix";  # optional, for theming
```

`hm-wrapper-modules` provides three things:
- `lib.wrapHomeModule` — evaluates HM modules and extracts their config
- `lib.mkBinds` — generates bubblewrap bind mount mappings
- `lib.modules.bwrapConfig` — standalone bubblewrap presentation module

## Step 2: The wrapping helper

In `modules/wrapped-packages.nix`, a `mkWrapped` helper does the heavy lifting:

```nix
mkWrapped = name: homeModules:
  let
    base = wlib.wrapHomeModule {
      inherit pkgs homeModules;
      programName = name;
      home-manager = inputs.home-manager;
    };
  in
  base.wrap ({ config, lib, ... }: {
    imports = [ wlib.modules.bwrapConfig ];
    bwrapConfig.binds.ro = wlib.mkBinds base.passthru.hmAdapter;
    env.XDG_CONFIG_HOME = lib.mkIf config.bwrapConfig.enable (lib.mkForce null);
  });
```

What this does:

1. **`wrapHomeModule`** evaluates your HM modules in a real home-manager
   context, extracts `home.packages`, `xdg.configFile`, `home.file`,
   `home.sessionVariables`, and activation scripts.

2. **`base.wrap`** extends the resulting wrapper with bubblewrap. On Linux,
   `bwrapConfig` creates a mount namespace where bundled config files appear
   at their expected `$HOME` paths (e.g., `~/.config/bat/config`) without
   modifying your real filesystem.

3. **`mkBinds`** generates the source→target bind mount mapping from the
   adapter's extracted file list.

4. **`XDG_CONFIG_HOME` is nulled** when bwrap is active — bwrap already
   presents files at the right paths, so the env override is redundant. On
   macOS where bwrap is a no-op, the adapter's `XDG_CONFIG_HOME` fallback
   still works.

## Step 3: Wrapping a simple program (bat)

The simplest case — a program with static config and no external context:

```nix
bat = mkWrapped "bat" [
  ({ ... }: {
    programs.bat = {
      enable = true;
      config.theme = "ansi";
    };
  })
];
```

This produces a wrapped `bat` where `~/.config/bat/config` contains
`--theme=ansi`. The HM module generates the config file; the adapter
extracts it; bwrap presents it.

```bash
nix run .#bat -- --list-themes   # bat sees the bundled config
```

## Step 4: Wrapping with stylix theming (alacritty)

Stylix auto-themes programs when imported as an HM module. Pass it alongside
your program config:

```nix
alacritty = mkWrapped "alacritty" [
  inputs.stylix.homeManagerModules.stylix
  ({ pkgs, ... }: {
    stylix = {
      enable = true;
      base16Scheme = "${pkgs.base16-schemes}/share/themes/catppuccin-mocha.yaml";
      fonts.monospace = {
        package = pkgs.nerd-fonts.jetbrains-mono;
        name = "JetBrainsMono Nerd Font";
      };
      # ... other font/theme settings
    };
    programs.alacritty = {
      enable = true;
      settings.window.padding = { x = 8; y = 8; };
      # Colors, fonts, and opacity are injected by stylix automatically.
    };
  })
];
```

Stylix generates the full `alacritty.toml` with catppuccin-mocha colors,
JetBrainsMono font, and your window settings merged together. The adapter
extracts this generated config from `xdg.configFile` and bundles it.

```bash
nix run .#alacritty   # launches with catppuccin theme, custom fonts
```

## Step 5: Auto-discovery

Notice that `mainPackage` is not specified in any of these calls. The adapter
auto-discovers it by:

1. Checking `programs.<name>.package` (e.g., `programs.bat.package`)
2. Matching `home.packages` by pname or `meta.mainProgram`
3. Falling back to the first enabled program with a package

The `programName` parameter (set to the attribute name by `mkWrapped`) hints
which program to look for.

## Step 6: Run it

```bash
# Individual programs
nix run .#bat
nix run .#starship
nix run .#alacritty

# Dev shell with all wrapped packages on PATH
nix develop
```

## How it works under the hood

The wrapper derivation output looks like:

```
$out/
├── bin/bat                    # wrapper script
├── hm-xdg-config/            # extracted XDG config files
│   └── bat/
│       └── config
├── hm-home/                   # extracted home.file entries
└── share/, man/, ...          # symlinked from original package
```

The `bin/bat` wrapper script:
1. Sets environment variables (session variables from HM, PATH for extra packages)
2. On Linux: execs via `bwrap --dev-bind / / --ro-bind $out/hm-xdg-config/bat ~/.config/bat ...`
3. On macOS: sets `XDG_CONFIG_HOME=$out/hm-xdg-config` and execs directly

Bubblewrap creates a mount namespace where the bundled config appears at
`~/.config/bat/config` while the rest of your filesystem (themes, fonts,
GTK config) remains visible through `--dev-bind / /`.

## Going further

- **Tier 2 programs** (identity-dependent): Pass user context via
  `extraSpecialArgs` or additional `homeModules`
- **Activation scripts**: Set `runActivation = true` for programs that need
  runtime setup (e.g., GitKraken's `gk-configure`)
- **Read-write state**: Use `bwrapConfig.binds.rw` for directories the
  program needs to write to
- **Inspect extracted data**: Access `base.passthru.hmAdapter` for the raw
  extracted packages, files, session variables, and activation scripts
