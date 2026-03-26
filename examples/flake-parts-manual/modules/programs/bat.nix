{
  flake.modules.homeManager.bat =
    { ... }:
    {
      programs.bat = {
        enable = true;
        config = {
          pager = "less -FR";
          italic-text = "always";
          style = "numbers,changes,header";
        };
      };
    };
}
