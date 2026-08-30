{
  config,
  pkgs,
  lib,
  ...
}:
{
  services.xserver.enable = true;
  services.desktopManager.gnome.enable = true;

  environment.systemPackages = with pkgs; [
    gnome.nautilus
  ];
}
