{ inputs, ... }:
{
  flake.modules.homeManager.stylix =
    { pkgs, ... }:
    {
      imports = [ inputs.stylix.homeManagerModules.stylix ];

      stylix = {
        enable = true;
        base16Scheme = "${pkgs.base16-schemes}/share/themes/catppuccin-mocha.yaml";

        fonts = {
          monospace = {
            package = pkgs.nerd-fonts.jetbrains-mono;
            name = "JetBrainsMono Nerd Font";
          };
          sansSerif = {
            package = pkgs.inter;
            name = "Inter";
          };
          serif = {
            package = pkgs.noto-fonts;
            name = "Noto Serif";
          };
          emoji = {
            package = pkgs.noto-fonts-emoji;
            name = "Noto Color Emoji";
          };
        };

        image = pkgs.runCommand "placeholder.png" { nativeBuildInputs = [ pkgs.imagemagick ]; } ''
          magick -size 1x1 xc:black $out
        '';
      };
    };
}
