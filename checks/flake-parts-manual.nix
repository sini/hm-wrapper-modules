{
  pkgs,
  self,
  home-manager,
}:
let
  wlib = self.lib;

  wrapped = wlib.wrapHomeModule {
    inherit pkgs;
    programName = "hello";
    homeModules = [
      (
        { ... }:
        {
          home.packages = [ pkgs.hello ];
        }
      )
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
