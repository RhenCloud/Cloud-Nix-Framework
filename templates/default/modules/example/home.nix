{
  config,
  lib,
  ...
}:
{
  home.sessionVariables.CLOUD_EXAMPLE = lib.mkIf config.cloud.example.enable "home:enabled";
}
