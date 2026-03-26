{
  pkgs,
  self,
  home-manager,
}:
let
  wlib = self.lib;
  testSource = pkgs.writeText "test-source-content" "source-file-data";
  wrapped = wlib.wrapHomeModule {
    inherit pkgs home-manager;
    homeModules = [
      (
        { ... }:
        {
          home.packages = [ pkgs.hello ];
          home.file.".test-source-file".source = testSource;
        }
      )
    ];
    mainPackage = pkgs.hello;
  };
in
pkgs.runCommand "hm-adapter-source-test" { } ''
  echo "=== Testing source file extraction ==="
  wrapperDrv="${wrapped.wrapper}"
  if [[ ! -f "$wrapperDrv/hm-home/.test-source-file" ]]; then
    echo "FAIL: source file should exist at hm-home/.test-source-file"
    find "$wrapperDrv" -type f || true
    exit 1
  fi
  if ! grep -q "source-file-data" "$wrapperDrv/hm-home/.test-source-file"; then
    echo "FAIL: source file should contain expected content"
    cat "$wrapperDrv/hm-home/.test-source-file"
    exit 1
  fi
  echo "PASS: source file extracted with correct content"
  touch $out
''
