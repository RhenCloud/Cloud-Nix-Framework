{
  description = "Cloud Nix Framework 模板";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    cloud = {
      url = "github:RhenCloud/Cloud-Nix-Framework";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.home-manager.follows = "home-manager";
    };
  };

  outputs = inputs: inputs.cloud.lib.mkFlake { inherit inputs; };
}
