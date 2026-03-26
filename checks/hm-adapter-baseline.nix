{
  pkgs,
  self,
  home-manager,
}:
let
  wlib = self.lib;
  wrapped = wlib.wrapHomeModule {
    inherit pkgs home-manager;
    homeModules = [
      (
        { ... }:
        {
          home.packages = [ pkgs.hello ];
        }
      )
    ];
    mainPackage = pkgs.hello;
  };
in
pkgs.runCommand "hm-adapter-baseline-test" { } ''
  echo "=== Testing baseline diff filtering ==="
  wrapperDrv="${wrapped.wrapper}"
  if [[ -f "$wrapperDrv/hm-home/.cache/.keep" ]]; then
    echo "FAIL: .cache/.keep should be filtered by baseline diff"
    exit 1
  fi
  echo "PASS: .cache/.keep filtered"
  if find "$wrapperDrv/hm-home" -name "tray.target" 2>/dev/null | grep -q .; then
    echo "FAIL: tray.target should be filtered"
    exit 1
  fi
  echo "PASS: tray.target filtered"
  if find "$wrapperDrv/hm-home" -path "*/environment.d/*" 2>/dev/null | grep -q .; then
    echo "FAIL: environment.d should be filtered"
    exit 1
  fi
  echo "PASS: environment.d filtered"
  echo "PASS: baseline diff filtering works"
  touch $out
''
