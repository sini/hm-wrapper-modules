{
  flake.modules.homeManager.alacritty =
    { ... }:
    {
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
      };
    };
}
