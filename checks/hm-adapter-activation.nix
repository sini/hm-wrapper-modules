{
  pkgs,
  self,
  home-manager,
}:
let
  wlib = self.lib;
  testHomeModule =
    { lib, ... }:
    {
      home.packages = [ pkgs.hello ];
      home.activation.testActivation = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        $DRY_RUN_CMD echo "activation-marker"
      '';
    };
  wrappedDefault = wlib.wrapHomeModule {
    inherit pkgs home-manager;
    homeModules = [ testHomeModule ];
    mainPackage = pkgs.hello;
  };
  wrappedWithActivation = wlib.wrapHomeModule {
    inherit pkgs home-manager;
    homeModules = [ testHomeModule ];
    mainPackage = pkgs.hello;
    runActivation = true;
  };
in
pkgs.runCommand "hm-adapter-activation-test" { } ''
  echo "=== Testing activation script handling ==="
  defaultScript="${wrappedDefault.wrapper}/bin/hello"
  if grep -q "activation-marker" "$defaultScript" 2>/dev/null; then
    echo "FAIL: activation should NOT be in wrapper with runActivation=false"
    exit 1
  fi
  echo "PASS: activation not in wrapper by default"
  activatedScript="${wrappedWithActivation.wrapper}/bin/hello"
  if ! grep -q "activation-marker" "$activatedScript" 2>/dev/null; then
    echo "FAIL: activation should be in wrapper with runActivation=true"
    cat "$activatedScript"
    exit 1
  fi
  echo "PASS: activation in wrapper with runActivation=true"
  if ! grep -q 'DRY_RUN_CMD=""' "$activatedScript" 2>/dev/null; then
    echo "FAIL: DRY_RUN_CMD should be stubbed"
    exit 1
  fi
  echo "PASS: HM activation variables stubbed"
  touch $out
''
