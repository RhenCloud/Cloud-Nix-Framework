{
  lib,
  ...
}:
{
  options.cloud.example = {
    message = lib.mkOption {
      type = lib.types.str;
      default = "hello";
    };
  };
}
