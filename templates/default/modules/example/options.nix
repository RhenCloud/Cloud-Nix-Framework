{
  options,
  config,
  lib,
  ...
}:
with lib;
{
  options.snowveil.example = {
    enable = mkEnableOption "example module";

    message = mkOption {
      type = types.str;
      default = "Hello from Snowveil";
      description = "Custom message for the example module";
    };
  };
}
