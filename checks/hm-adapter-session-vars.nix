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
          home.sessionVariables = {
            EDITOR = "vim";
            PAGER = "less";
          };
        }
      )
    ];
    mainPackage = pkgs.hello;
  };
in
pkgs.runCommand "hm-adapter-session-vars-test" { } ''
  echo "=== Testing session variable extraction ==="
  wrapperScript="${wrapped.wrapper}/bin/hello"
  if ! grep -q "EDITOR" "$wrapperScript" 2>/dev/null; then
    echo "FAIL: wrapper should set EDITOR"
    cat "$wrapperScript"
    exit 1
  fi
  echo "PASS: EDITOR extracted"
  if ! grep -q "PAGER" "$wrapperScript" 2>/dev/null; then
    echo "FAIL: wrapper should set PAGER"
    cat "$wrapperScript"
    exit 1
  fi
  echo "PASS: PAGER extracted"
  touch $out
''
