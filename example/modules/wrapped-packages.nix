# Wrap home-manager programs as standalone `nix run`-able packages.
#
# Each entry evaluates an HM module, extracts its config, and produces
# a wrapped derivation. On Linux, bubblewrap presents the bundled config
# at the expected filesystem paths without modifying $HOME.
{ inputs, ... }:
{
  perSystem =
    { pkgs, ... }:
    let
      wlib = inputs.hm-wrapper-modules.lib;

      # Helper: wrap an HM module with bwrap on Linux, XDG fallback on darwin.
      mkWrapped =
        name: homeModules:
        let
          base = wlib.wrapHomeModule {
            inherit pkgs homeModules;
            programName = name;
            home-manager = inputs.home-manager;
          };
        in
        base.wrap (
          { config, lib, ... }:
          {
            imports = [ wlib.modules.bwrapConfig ];
            bwrapConfig.binds.ro = wlib.mkBinds base.passthru.hmAdapter;
            # Null out XDG_CONFIG_HOME when bwrap is active — bwrap presents
            # files at their real paths, so the env override is unnecessary.
            # On darwin, bwrap is a no-op and the adapter's mkDefault
            # XDG_CONFIG_HOME is the only way programs find their config.
            env.XDG_CONFIG_HOME = lib.mkIf config.bwrapConfig.enable (lib.mkForce null);
          }
        );
    in
    {
      packages = {

        # Tier 1: no context needed — static program config
        bat = mkWrapped "bat" [
          (
            { ... }:
            {
              programs.bat = {
                enable = true;
                config.theme = "ansi";
              };
            }
          )
        ];

        starship = mkWrapped "starship" [
          (
            { ... }:
            {
              programs.starship = {
                enable = true;
                settings = {
                  add_newline = false;
                  character.success_symbol = "[>](bold green)";
                  character.error_symbol = "[x](bold red)";
                };
              };
            }
          )
        ];

        # Alacritty with stylix theming.
        # Stylix auto-themes alacritty (colors, fonts, opacity) when both
        # are enabled. The adapter extracts the generated alacritty.toml
        # from xdg.configFile and bundles it into the wrapper.
        alacritty = mkWrapped "alacritty" [
          inputs.stylix.homeManagerModules.stylix
          (
            { pkgs, ... }:
            {
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
                # Stylix requires an image even if unused for color generation.
                # Use a tiny placeholder when deriving colors from base16Scheme.
                image = pkgs.runCommand "placeholder.png" { nativeBuildInputs = [ pkgs.imagemagick ]; } ''
                  magick -size 1x1 xc:black $out
                '';
              };

              programs.alacritty = {
                enable = true;
                settings = {
                  window = {
                    decorations = "full";
                    dynamic_title = true;
                    padding = {
                      x = 8;
                      y = 8;
                    };
                  };
                  scrolling.history = 10000;
                };
                # Colors, fonts, and opacity are injected by stylix automatically.
              };
            }
          )
        ];

      };
    };
}
