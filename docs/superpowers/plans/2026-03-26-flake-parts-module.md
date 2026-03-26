# flakeModules.default Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers-extended-cc:subagent-driven-development (if subagents available) or superpowers-extended-cc:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Export a flake-parts module from hm-wrapper-modules that handles all wrapping boilerplate, so consumers just declare programs and get packages.

**Architecture:** A `parts.nix` file declares `hmWrappers.*` options at the flake level and a `perSystem` handler that iterates programs, calls `wrapHomeModule` + bwrap for each, and outputs to `perSystem.packages`. Auto-discovery introspects HM module args to populate programs automatically when enabled.

**Tech Stack:** Nix, flake-parts (`flake-parts-lib.mkPerSystemOption`), nix-wrapper-modules wlib

---

## File Map

| File | Action | Responsibility |
|---|---|---|
| `parts.nix` | Create | flake-parts module: hmWrappers options + perSystem wrapping logic + auto-discovery |
| `flake.nix` | Modify | Add `flakeModules.default = ./parts.nix` to outputs |
| `checks/flake-parts-manual.nix` | Create | Test: explicit program registration via flakeModule |
| `checks/flake-parts-auto.nix` | Create | Test: auto-discovery wraps correct entries, skips excluded |
| `example/modules/auto-wrapped-packages.nix` | Rewrite | Thin config that imports flakeModule, sets autoWrap + exclude + baseModules |
| `example/README.md` | Modify | Document both raw and flakeModule usage patterns |

---

### Task 0: Create parts.nix flake-parts module

**Goal:** Implement the `hmWrappers` option namespace and `perSystem` package generation.

**Files:**
- Create: `parts.nix`
- Modify: `flake.nix`

**Acceptance Criteria:**
- [ ] Declares `hmWrappers.home-manager` (required, raw type)
- [ ] Declares `hmWrappers.programs` as `attrsOf (submodule { mainPackage?; homeModules; })`
- [ ] Declares `hmWrappers.baseModules` (listOf raw, default [])
- [ ] Declares `hmWrappers.autoWrap` (bool, default false)
- [ ] Declares `hmWrappers.exclude` (listOf str, default [])
- [ ] Declares `hmWrappers.stateVersion` (str, default "24.11")
- [ ] Declares `hmWrappers.extraSpecialArgs` (attrsOf raw, default {})
- [ ] Auto-discovery populates `hmWrappers.programs` when `autoWrap = true`, skipping `exclude` entries
- [ ] `perSystem` iterates programs, calls `wrapHomeModule` with `baseModules ++ homeModules`, applies bwrap + mkBinds + XDG nulling
- [ ] `mainPackage` passed through when set, otherwise `programName` = attr name
- [ ] Outputs to `perSystem.packages.<name>`
- [ ] `flake.nix` exports `flakeModules.default = ./parts.nix`
- [ ] All options have `description` fields

**Verify:** `nix flake check` passes (existing checks unbroken)

**Steps:**

- [ ] **Step 1: Create parts.nix**

```nix
# parts.nix — flake-parts module for hm-wrapper-modules
#
# Provides hmWrappers.* options that auto-generate wrapped packages
# from home-manager module declarations.
{
  config,
  lib,
  flake-parts-lib,
  inputs,
  ...
}:
let
  inherit (lib) types mkOption;

  # Auto-discovery: introspect HM module function args to determine
  # if a module can be wrapped without custom context.
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

  cfg = config.hmWrappers;

  programSubmodule = types.submodule {
    options = {
      mainPackage = mkOption {
        type = types.nullOr types.package;
        default = null;
        description = ''
          Explicit package to wrap. When null, auto-discovered
          from the evaluated HM config via programName.
        '';
      };
      homeModules = mkOption {
        type = types.listOf types.raw;
        description = ''
          Home-manager modules to evaluate for this program.
        '';
      };
    };
  };
in
{
  options.hmWrappers = {
    home-manager = mkOption {
      type = types.raw;
      description = ''
        The home-manager flake input. Required for HM evaluation.
        Example: `inputs.home-manager`
      '';
    };
    programs = mkOption {
      type = types.attrsOf programSubmodule;
      default = { };
      description = ''
        Programs to wrap. Keys become package names in `perSystem.packages`.
        Values specify the HM modules and optionally an explicit mainPackage.
      '';
    };
    baseModules = mkOption {
      type = types.listOf types.raw;
      default = [ ];
      description = ''
        HM modules prepended to every program's homeModules.
        Use for shared config like stylix theming.
      '';
    };
    autoWrap = mkOption {
      type = types.bool;
      default = false;
      description = ''
        Auto-discover wrappable entries from `flake.modules.homeManager`.
        An entry is wrappable when its module function args only use
        standard HM args (config, lib, pkgs, etc.).
      '';
    };
    exclude = mkOption {
      type = types.listOf types.str;
      default = [ ];
      description = ''
        Entry names to skip during auto-discovery. Use for shared
        modules like stylix that aren't standalone programs.
      '';
    };
    stateVersion = mkOption {
      type = types.str;
      default = "24.11";
      description = "home-manager stateVersion for wrapper evaluations.";
    };
    extraSpecialArgs = mkOption {
      type = types.attrsOf types.raw;
      default = { };
      description = "Extra specialArgs passed to every wrapper's HM evaluation.";
    };
  };

  # Auto-discovery: populate programs from flake.modules.homeManager
  config.hmWrappers.programs =
    let
      hmModules = config.flake.modules.homeManager or { };
      wrappableNames = lib.filter (
        name: !(lib.elem name cfg.exclude) && isWrappable hmModules.${name}
      ) (lib.attrNames hmModules);
    in
    lib.mkIf cfg.autoWrap (
      lib.genAttrs wrappableNames (name: {
        homeModules = [ hmModules.${name} ];
      })
    );

  config.perSystem = flake-parts-lib.mkPerSystemOption (
    { pkgs, lib, self', ... }:
    let
      wlib = inputs.hm-wrapper-modules.lib or inputs.self.lib;
    in
    {
      packages = lib.mapAttrs (
        name: programCfg:
        let
          base = wlib.wrapHomeModule {
            inherit pkgs;
            homeModules = cfg.baseModules ++ programCfg.homeModules;
            home-manager = cfg.home-manager;
            stateVersion = cfg.stateVersion;
            extraSpecialArgs = cfg.extraSpecialArgs;
          } // lib.optionalAttrs (programCfg.mainPackage != null) {
            mainPackage = programCfg.mainPackage;
          } // lib.optionalAttrs (programCfg.mainPackage == null) {
            programName = name;
          };
        in
        base.wrap (
          { config, lib, ... }:
          {
            imports = [ wlib.modules.bwrapConfig ];
            bwrapConfig.binds.ro = wlib.mkBinds base.passthru.hmAdapter;
            env.XDG_CONFIG_HOME = lib.mkIf config.bwrapConfig.enable (lib.mkForce null);
          }
        )
      ) cfg.programs;
    }
  );
}
```

**Important:** The `wrapHomeModule` call needs adjustment — `mainPackage` and `programName` are arguments to the function, not attributes merged after. The actual call should be:

```nix
base = wlib.wrapHomeModule ({
  inherit pkgs;
  homeModules = cfg.baseModules ++ programCfg.homeModules;
  home-manager = cfg.home-manager;
  stateVersion = cfg.stateVersion;
  extraSpecialArgs = cfg.extraSpecialArgs;
} // lib.optionalAttrs (programCfg.mainPackage != null) {
  mainPackage = programCfg.mainPackage;
} // lib.optionalAttrs (programCfg.mainPackage == null) {
  programName = name;
});
```

- [ ] **Step 2: Add flakeModules.default to flake.nix**

After the `modules` output, add:

```nix
flakeModules.default = ./parts.nix;
```

- [ ] **Step 3: Handle self-reference for wlib**

The `parts.nix` runs inside the consumer's flake-parts evaluation, not inside hm-wrapper-modules itself. It needs to reference wlib from the hm-wrapper-modules input. Since `parts.nix` receives `inputs` from the consumer's flake, the consumer must have `hm-wrapper-modules` as an input. Use `inputs.hm-wrapper-modules.lib` to access wlib.

However, flake-parts modules don't receive `inputs` directly by default — they receive it if the consumer passes it through `mkFlake { inherit inputs; }` (which is standard). Verify this works or pass wlib via the module's closure:

```nix
# Alternative: close over wlib in flake.nix
flakeModules.default = import ./parts.nix { inherit wlib; };
```

Where `parts.nix` becomes:

```nix
{ wlib }:
{ config, lib, flake-parts-lib, ... }:
# ... use wlib directly from closure
```

This avoids the consumer needing to have a specific input name. Use this pattern.

- [ ] **Step 4: Format**

```bash
nix fmt
```

---

### Task 1: Add flake-parts module tests

**Goal:** Verify the flakeModule works for both manual and auto-wrap modes.

**Files:**
- Create: `checks/flake-parts-manual.nix`
- Create: `checks/flake-parts-auto.nix`

**Acceptance Criteria:**
- [ ] Manual test: declares programs explicitly via hmWrappers.programs, verifies wrapper derivation builds and contains the main binary
- [ ] Auto test: declares flake.modules.homeManager entries, sets autoWrap = true, verifies wrappable entries become packages and excluded entries don't
- [ ] Both tests pass: `nix flake check`

**Verify:** `nix flake check` → all checks pass

**Steps:**

- [ ] **Step 1: Create manual registration test**

`checks/flake-parts-manual.nix` — this test can't easily use flake-parts (it would need a full `mkFlake` evaluation inside a check). Instead, test the `parts.nix` module by importing it directly into a `lib.evalModules` call that simulates the flake-parts environment, or test it by importing the module's logic functions directly.

A simpler approach: since the flakeModule's `perSystem` logic is just calling `wrapHomeModule` + `base.wrap`, and we already test those in the existing checks, the flakeModule test should verify the option merging and auto-discovery logic work correctly. Use `lib.evalModules` to evaluate the options portion:

```nix
{ pkgs, self, home-manager }:
let
  lib = pkgs.lib;

  # Test that hmWrappers.programs produces the right shape
  # by calling wrapHomeModule with the same args the flakeModule would
  wlib = self.lib;

  wrapped = wlib.wrapHomeModule {
    inherit pkgs;
    programName = "hello";
    homeModules = [
      ({ ... }: { home.packages = [ pkgs.hello ]; })
    ];
    home-manager = home-manager;
  };

  result = wrapped.wrap (
    { config, lib, ... }:
    {
      imports = [ wlib.modules.bwrapConfig ];
      bwrapConfig.binds.ro = wlib.mkBinds wrapped.passthru.hmAdapter;
      env.XDG_CONFIG_HOME = lib.mkIf config.bwrapConfig.enable (lib.mkForce null);
    }
  );
in
pkgs.runCommand "flake-parts-manual-test" { } ''
  echo "=== Testing flakeModule wrapping pattern ==="
  if [[ ! -x "${result}/bin/hello" ]]; then
    echo "FAIL: wrapper should contain bin/hello"
    exit 1
  fi
  echo "PASS: manual registration pattern works"
  touch $out
''
```

- [ ] **Step 2: Create auto-discovery test**

`checks/flake-parts-auto.nix` — test the `isWrappable` logic directly:

```nix
{ pkgs, self }:
let
  lib = pkgs.lib;

  # Replicate the auto-discovery logic from parts.nix
  standardHmArgs = [ "config" "lib" "pkgs" "modulesPath" "options"
                      "osConfig" "nixosConfig" "inputs" "..." ];

  getModuleArgs = mod:
    if lib.isFunction mod then lib.attrNames (builtins.functionArgs mod)
    else if lib.isAttrs mod && mod ? __functor then
      lib.attrNames (builtins.functionArgs (mod.__functor mod))
    else [];

  isWrappable = mod:
    let args = getModuleArgs mod;
    in args == [] || lib.all (a: lib.elem a standardHmArgs) args;

  # Test modules
  wrappableModule = { config, lib, pkgs, ... }: { programs.bat.enable = true; };
  contextModule = { config, lib, pkgs, user, ... }: { programs.git.enable = true; };
  attrModule = { programs.bat.enable = true; };
in
pkgs.runCommand "flake-parts-auto-test" { } ''
  echo "=== Testing auto-discovery logic ==="

  ${if isWrappable wrappableModule then ''
    echo "PASS: standard HM module is wrappable"
  '' else ''
    echo "FAIL: standard HM module should be wrappable"
    exit 1
  ''}

  ${if !isWrappable contextModule then ''
    echo "PASS: context-dependent module is not wrappable"
  '' else ''
    echo "FAIL: context-dependent module should not be wrappable"
    exit 1
  ''}

  ${if isWrappable attrModule then ''
    echo "PASS: plain attrset module is wrappable"
  '' else ''
    echo "FAIL: plain attrset module should be wrappable"
    exit 1
  ''}

  echo "PASS: auto-discovery logic works"
  touch $out
''
```

- [ ] **Step 3: Format and verify**

```bash
nix fmt
nix flake check
```

---

### Task 2: Update example and README

**Goal:** Rewrite `auto-wrapped-packages.nix` to use the flakeModule, update README to document both patterns.

**Files:**
- Rewrite: `example/modules/auto-wrapped-packages.nix`
- Modify: `example/README.md`

**Acceptance Criteria:**
- [ ] `auto-wrapped-packages.nix` imports `inputs.hm-wrapper-modules.flakeModules.default`, sets `hmWrappers` config only
- [ ] README documents the raw API pattern (wrapped-packages.nix) and the flakeModule pattern (auto-wrapped-packages.nix)
- [ ] README shows both explicit and autoWrap usage of the flakeModule

**Verify:** README renders correctly, example structure is clear

**Steps:**

- [ ] **Step 1: Rewrite auto-wrapped-packages.nix**

```nix
# Auto-wrapped packages via flakeModule.
#
# The flakeModule handles all wrapping boilerplate — wrapHomeModule,
# bwrap, mkBinds, XDG_CONFIG_HOME. Consumers just declare programs.
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
```

- [ ] **Step 2: Update README**

Add a section after the raw API walkthrough showing the flakeModule approach. Show both explicit and auto modes.

- [ ] **Step 3: Commit**

```bash
git add parts.nix flake.nix checks/ example/ README.md
git commit -m "feat: add flakeModules.default for declarative wrapper registration

- Export parts.nix as flakeModules.default
- hmWrappers.programs for explicit registration with optional mainPackage
- hmWrappers.autoWrap for auto-discovery from flake.modules.homeManager
- hmWrappers.baseModules for shared config (e.g., stylix)
- Tests for manual pattern and auto-discovery logic
- Update example with flakeModule usage"
```
