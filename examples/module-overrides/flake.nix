{
  description = "Cloud Nix Framework - Module Overrides Example";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-24.05";
    cloud.url = "path:../..";
    cloud.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = { self, nixpkgs, cloud }: 
    cloud.lib.mkFlake {
      inherit self;
      inputs = { inherit nixpkgs; };
      systems = [ "x86_64-linux" ];
      root = ./.;
    };
}
