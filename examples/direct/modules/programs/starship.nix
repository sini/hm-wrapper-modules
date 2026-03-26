{
  flake.modules.homeManager.starship =
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
    };
}
