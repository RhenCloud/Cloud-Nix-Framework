{
  config,
  lib,
  ...
}:
{
  home.sessionVariables.SNOWVEIL_EXAMPLE = lib.mkIf config.snowveil.example.enable "home:enabled";
}
