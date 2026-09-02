{
  config,
  lib,
  ...
}:
{
  environment.variables.SNOWVEIL_EXAMPLE = lib.mkIf config.snowveil.example.enable "nixos:enabled";
}
