# A dev shell that includes the wrapped packages for quick testing.
{ inputs, ... }:
{
  perSystem =
    { pkgs, config, ... }:
    {
      devShells.default = pkgs.mkShell {
        packages = builtins.attrValues config.packages;
      };
    };
}
