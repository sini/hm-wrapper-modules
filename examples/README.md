# Examples

Three example flakes showing different approaches to wrapping home-manager
programs. All three produce the same packages (`bat`, `starship`, `alacritty`)
from the same HM module declarations — they differ only in how the wrapping
is configured.

```
nix run ./examples/direct#bat
nix run ./examples/flake-parts-manual#bat
nix run ./examples/flake-parts-auto#bat
```

## direct/

Full control. Each package is wrapped inline using `wlib.wrapHomeModule` +
`wlib.modules.bwrapConfig` + `wlib.mkBinds`. Shows three call patterns:
auto-discovered package, explicit `mainPackage`, and composed with stylix.

Best for: power users, per-program customization, understanding the mechanics.

## flake-parts-manual/

Uses `flakeModules.default` from hm-wrapper-modules. Programs are registered
explicitly in `perSystem.hmWrappers.programs`. The flakeModule handles all
wrapping boilerplate.

Best for: explicit control over which programs are wrapped, with `pkgs` access
for `mainPackage`.

## flake-parts-auto/

Uses `flakeModules.default` with `autoWrap = true`. All wrappable entries in
`flake.modules.homeManager` become packages automatically. Non-program entries
(like `stylix`) are excluded. `baseModules` applies shared theming.

Best for: large configs where most HM programs should be wrappable with
minimal configuration.
