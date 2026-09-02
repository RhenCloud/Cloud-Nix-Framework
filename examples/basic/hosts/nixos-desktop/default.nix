{
  config,
  pkgs,
  ...
}:
{
  config = {
    boot.isContainer = true;

    system.stateVersion = "25.05";

    users.users.rhencloud = {
      isNormalUser = true;
      home = "/home/rhencloud";
    };

    networking.hostName = "nixos-desktop";

    environment = {
      systemPackages = [ pkgs.hello ];
      variables.SNOWVEIL_HOST_CONFIG_ARG = config.networking.hostName;
    };
  };
}
