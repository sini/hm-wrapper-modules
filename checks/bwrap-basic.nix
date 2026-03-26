{ pkgs, self }:
let
  wlib = self.lib;
  result =
    if !pkgs.stdenv.hostPlatform.isLinux then
      pkgs.runCommand "bwrap-basic-test-skip" { } ''
        echo "SKIP: bwrap tests only run on Linux"
        touch $out
      ''
    else
      let
        wrapped = wlib.evalPackage [
          wlib.modules.default
          wlib.modules.bwrapConfig
          {
            inherit pkgs;
            package = pkgs.hello;
            constructFiles.testConfig = {
              content = "theme = test-theme";
              relPath = "hm-xdg-config/bat/config";
            };
            bwrapConfig.binds.ro = {
              "${placeholder "out"}/hm-xdg-config/bat" = ".config/bat";
            };
          }
        ];
      in
      pkgs.runCommand "bwrap-basic-test" { } ''
        echo "=== Testing bwrapConfig module ==="
        wrapperScript="${wrapped}/bin/hello"

        if ! grep -q "bwrap" "$wrapperScript" 2>/dev/null; then
          echo "FAIL: wrapper should contain bwrap invocation"
          cat "$wrapperScript"
          exit 1
        fi
        echo "PASS: bwrap present in wrapper"

        if ! grep -q "\-\-dev-bind" "$wrapperScript" 2>/dev/null; then
          echo "FAIL: wrapper should contain --dev-bind"
          cat "$wrapperScript"
          exit 1
        fi
        echo "PASS: --dev-bind present"

        if ! grep -q "\-\-ro-bind" "$wrapperScript" 2>/dev/null; then
          echo "FAIL: wrapper should contain --ro-bind"
          cat "$wrapperScript"
          exit 1
        fi
        echo "PASS: --ro-bind present"

        if [[ ! -f "${wrapped}/hm-xdg-config/bat/config" ]]; then
          echo "FAIL: config file should exist in derivation"
          find "${wrapped}" -type f || true
          exit 1
        fi
        echo "PASS: config file in derivation"

        echo "PASS: all bwrap checks passed"
        touch $out
      '';
in
result
