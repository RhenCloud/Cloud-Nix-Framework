{
  pkgs,
  ...
}:
{
  system.stateVersion = "25.05";

  environment.systemPackages = [ pkgs.hello ];
}
