{
  system = "x86_64-linux";
  roles = [
    "desktop"
    "development"
  ];
  profiles = [
    "workstation"
    "personal"
  ];

  home.useGlobalPkgs = false;
}
