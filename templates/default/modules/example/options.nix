{
  options,
  config,
  lib,
  ...
}:
with lib;
{
  options.cloud.example = {
    enable = mkEnableOption "example module";

    message = mkOption {
      type = types.str;
      default = "Hello from Cloud Nix Framework";
      description = "Custom message for the example module";
    };
  };
}
