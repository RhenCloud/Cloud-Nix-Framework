{
  lib,
  hello,
}:
{
  type = "app";
  program = lib.getExe hello;
}
