{
  config,
  lib,
  ...
}:
{
  environment.variables.CLOUD_EXAMPLE = lib.mkIf config.cloud.example.enable "nixos:enabled";
}
