{
  flake.modules.homeManager.bat =
    { ... }:
    {
      programs.bat = {
        enable = true;
        config.theme = "ansi";
      };
    };
}
