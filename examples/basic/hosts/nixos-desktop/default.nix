{
  config,
  pkgs,
  ...
}:
{
  config = {
    boot.isContainer = true;

    system.stateVersion = "25.05";

    environment = {
      systemPackages = [ pkgs.hello ];
      variables.SNOWVEIL_HOST_CONFIG_ARG = config.networking.hostName;
    };
  };
}
