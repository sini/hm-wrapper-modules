{ pkgs, self }:
let
  lib = pkgs.lib;

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

  wrappableModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    {
      programs.bat.enable = true;
    };
  contextModule =
    {
      config,
      lib,
      pkgs,
      user,
      ...
    }:
    {
      programs.git.enable = true;
    };
  attrModule = {
    programs.bat.enable = true;
  };
in
pkgs.runCommand "flake-parts-auto-test" { } ''
  echo "=== Testing auto-discovery logic ==="

  ${
    if isWrappable wrappableModule then
      ''echo "PASS: standard HM module is wrappable"''
    else
      ''
        echo "FAIL: standard HM module should be wrappable"
        exit 1
      ''
  }

  ${
    if !isWrappable contextModule then
      ''echo "PASS: context-dependent module is not wrappable"''
    else
      ''
        echo "FAIL: context-dependent module should not be wrappable"
        exit 1
      ''
  }

  ${
    if isWrappable attrModule then
      ''echo "PASS: plain attrset module is wrappable"''
    else
      ''
        echo "FAIL: plain attrset module should be wrappable"
        exit 1
      ''
  }

  echo "PASS: auto-discovery logic works"
  touch $out
''
