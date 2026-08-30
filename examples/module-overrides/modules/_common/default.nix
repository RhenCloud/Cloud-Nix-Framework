{
  config,
  pkgs,
  lib,
  ...
}:
{
  system.stateVersion = "24.05";

  environment.systemPackages = with pkgs; [
    git
    vim
  ];
}
