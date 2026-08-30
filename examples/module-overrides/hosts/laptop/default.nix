{
  config,
  lib,
  pkgs,
  ...
}:
{
  networking.hostName = "laptop";
  boot.loader.systemd-boot.enable = true;
}
