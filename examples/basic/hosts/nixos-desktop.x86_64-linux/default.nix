{
  pkgs,
  ...
}:
{
  role = "desktop";
  config = {
    system.stateVersion = "25.05";

    environment.systemPackages = [ pkgs.hello ];
  };
}
