{
  lib,
  ...
}:
{
  options.snowveil.example = {
    message = lib.mkOption {
      type = lib.types.str;
      default = "hello";
    };
  };
}
