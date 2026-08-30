{
  config,
  lib,
  pkgs,
  ...
}:
{
  networking.hostName = "gaming-rig";
  boot.loader.grub.enable = true;
}
