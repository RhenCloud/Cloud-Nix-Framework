{
  lib,
  ...
}:
{
  options.cloud.example = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
    };
  };
}
