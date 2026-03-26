{
  pkgs,
  self,
  home-manager,
}:
let
  wlib = self.lib;

  # A minimal HM module for testing.
  # It exercises the three extraction paths: packages, files, and activation.
  testHomeModule =
    { config, lib, ... }:
    {
      home.packages = [
        pkgs.hello
        pkgs.cowsay
      ];

      xdg.configFile."test-app/config.ini".text = ''
        [settings]
        greeting = hello-from-hm
      '';

      home.file.".test-app-home".text = ''
        home-file-content
      '';

      home.activation.testActivation = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        $DRY_RUN_CMD echo "activation-marker"
      '';
    };

  # Wrap the test module using the adapter
  wrapped = wlib.wrapHomeModule {
    inherit pkgs home-manager;
    homeModules = [ testHomeModule ];
    mainPackage = pkgs.hello;
  };

in
pkgs.runCommand "hm-adapter-test" { } ''
  echo "=== Testing wrapHomeModule ==="

  wrapperDrv="${wrapped.wrapper}"

  # 1. The wrapper derivation should exist and contain the main binary
  if [[ ! -x "$wrapperDrv/bin/hello" ]]; then
    echo "FAIL: wrapper should contain bin/hello"
    ls -la "$wrapperDrv/bin/" || true
    exit 1
  fi
  echo "PASS: main binary (hello) present in wrapper"

  # 2. Extra packages: cowsay should be in PATH via extraPackages
  wrapperScript="$wrapperDrv/bin/hello"
  if ! grep -q "${pkgs.cowsay}" "$wrapperScript" 2>/dev/null; then
    echo "FAIL: wrapper script should reference cowsay package for PATH"
    cat "$wrapperScript"
    exit 1
  fi
  echo "PASS: extraPackages (cowsay) referenced in wrapper"

  # 3. XDG config file should be extracted
  if [[ ! -f "$wrapperDrv/hm-xdg-config/test-app/config.ini" ]]; then
    echo "FAIL: xdg config file should exist at hm-xdg-config/test-app/config.ini"
    find "$wrapperDrv" -type f || true
    exit 1
  fi
  if ! grep -q "hello-from-hm" "$wrapperDrv/hm-xdg-config/test-app/config.ini"; then
    echo "FAIL: xdg config file should contain expected content"
    cat "$wrapperDrv/hm-xdg-config/test-app/config.ini"
    exit 1
  fi
  echo "PASS: xdg config file extracted with correct content"

  # 4. XDG_CONFIG_HOME should be set in the wrapper
  if ! grep -q "XDG_CONFIG_HOME" "$wrapperScript" 2>/dev/null; then
    echo "FAIL: wrapper should set XDG_CONFIG_HOME"
    cat "$wrapperScript"
    exit 1
  fi
  echo "PASS: XDG_CONFIG_HOME set in wrapper"

  # 5. home.file should be extracted
  if [[ ! -f "$wrapperDrv/hm-home/.test-app-home" ]]; then
    echo "FAIL: home file should exist at hm-home/.test-app-home"
    find "$wrapperDrv" -type f || true
    exit 1
  fi
  if ! grep -q "home-file-content" "$wrapperDrv/hm-home/.test-app-home"; then
    echo "FAIL: home file should contain expected content"
    cat "$wrapperDrv/hm-home/.test-app-home"
    exit 1
  fi
  echo "PASS: home file extracted with correct content"

  # 6. Activation scripts should NOT be in wrapper by default (runActivation = false)
  if grep -q "activation-marker" "$wrapperScript" 2>/dev/null; then
    echo "FAIL: activation should NOT be in wrapper with default runActivation=false"
    exit 1
  fi
  echo "PASS: activation scripts not in wrapper by default"

  echo "PASS: all hm-adapter checks passed"
  touch $out
''
