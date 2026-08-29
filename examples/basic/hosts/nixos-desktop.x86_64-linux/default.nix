{
  pkgs,
  ...
}:
{
  config = {
    system.stateVersion = "25.05";

    cloud.role = "desktop";

    environment.systemPackages = [ pkgs.hello ];
  };
}
