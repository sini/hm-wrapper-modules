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
          home.sessionVariables.MY_VAR = "test-value";
        }
      )
    ];
    mainPackage = pkgs.hello;
  };
in
pkgs.runCommand "hm-adapter-minimal-test" { } ''
  echo "=== Testing minimal module ==="
  wrapperDrv="${wrapped.wrapper}"
  if [[ ! -x "$wrapperDrv/bin/hello" ]]; then
    echo "FAIL: wrapper should contain main binary"
    exit 1
  fi
  echo "PASS: minimal module builds"
  wrapperScript="$wrapperDrv/bin/hello"
  if ! grep -q "MY_VAR" "$wrapperScript" 2>/dev/null; then
    echo "FAIL: wrapper should set MY_VAR"
    cat "$wrapperScript"
    exit 1
  fi
  echo "PASS: session variable in minimal wrapper"
  touch $out
''
