{
  hosts = [
    "nixos-desktop"
    "hm-standalone"
  ];
  uid = 1000;
  extraGroups = [ "wheel" ];
}
