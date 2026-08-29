{
  description = "Cloud Nix Framework：基于 Nix Flakes 的配置框架";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      home-manager,
    }:
    let
      inherit (nixpkgs) lib;
      cloud = import ./lib { inherit lib; };
      frameworkInputs = {
        inherit self nixpkgs home-manager;
      };
      bound = cloud.mkLib { inputs = frameworkInputs; };

      templates = {
        default = {
          path = ./templates/default;
          description = "Cloud Nix Framework 最小可用模板";
        };
      };

      exampleInputs = {
        inherit nixpkgs home-manager;
        self = {
          outPath = ./examples/basic;
        };
      };
      exampleFlake = cloud.mkFlake {
        inputs = exampleInputs;
      };

      systems = [
        "x86_64-linux"
        "aarch64-linux"
      ];

      checksFor =
        sys:
        let
          pkgs = nixpkgs.legacyPackages.${sys};
          exampleHost = exampleFlake.nixosConfigurations.nixos-desktop;
          exampleHome = exampleFlake.homeConfigurations."rhencloud@nixos-desktop";
          exampleHomeGlobal = exampleFlake.homeConfigurations.rhencloud;
          examplePkg = exampleFlake.packages.${sys}.hello;
          exampleDevshell = exampleFlake.devShells.${sys}.default;
          exampleOverlay = exampleFlake.overlays.example;
          exampleLib = exampleFlake.lib.example.shout;
        in
        {
          surface = pkgs.runCommand "cloud-surface" { } ''
            printf '%s\n' "${builtins.concatStringsSep " " (builtins.attrNames cloud)}" > "$out"
          '';
          host = pkgs.runCommand "cloud-host" { } ''
            printf '%s\n' "${toString exampleHost.config.cloud.users}" > "$out"
          '';
          home = pkgs.runCommand "cloud-home" { } ''
            printf '%s\n' "${exampleHome.config.home.username}" > "$out"
          '';
          homeGlobal = pkgs.runCommand "cloud-home-global" { } ''
            printf '%s\n' "${exampleHomeGlobal.config.home.username}" > "$out"
          '';
          package = pkgs.runCommand "cloud-package" { } ''
            printf '%s\n' "${examplePkg.name}" > "$out"
          '';
          overlay = pkgs.runCommand "cloud-overlay" { } ''
            printf '%s\n' "${if builtins.isFunction exampleOverlay then "ok" else "bad"}" > "$out"
          '';
          devshell = pkgs.runCommand "cloud-devshell" { } ''
            printf '%s\n' "${if exampleDevshell ? name then "ok" else "bad"}" > "$out"
          '';
          userlib = pkgs.runCommand "cloud-userlib" { } ''
            printf '%s\n' "${exampleLib "hi"}" > "$out"
          '';
          images = pkgs.runCommand "cloud-images" { } ''
            printf '%s\n' "${toString (builtins.attrNames exampleFlake.images)}" > "$out"
          '';
          rolefilter = pkgs.runCommand "cloud-rolefilter" { } ''
            if [ -n "${exampleHost.config.environment.variables.CLOUD_SERVER or ""}" ]; then
              echo "server 角色模块应被过滤掉，但未" >&2
              exit 1
            fi
            printf '%s\n' "${exampleHost.config.environment.variables.CLOUD_EXAMPLE}" > "$out"
          '';
        };

      checks = lib.genAttrs systems checksFor;

      devShells = lib.genAttrs systems (
        sys:
        let
          pkgs = nixpkgs.legacyPackages.${sys};
        in
        {
          default = pkgs.mkShell {
            packages = [
              pkgs.nix
              pkgs.nixfmt
              pkgs.deadnix
              pkgs.statix
              pkgs.nodejs
              pkgs.treefmt
              pkgs.mdformat
            ];
          };
        }
      );

      formatter = lib.genAttrs systems (
        sys:
        let
          pkgs = nixpkgs.legacyPackages.${sys};
          tools = [
            pkgs.treefmt
            pkgs.nixfmt
            pkgs.mdformat
            pkgs.statix
            pkgs.deadnix
          ];
          config = pkgs.writeText "treefmt.toml" (builtins.readFile ./treefmt.toml);
        in
        pkgs.writeShellScriptBin "fmt" ''
          export PATH=${pkgs.lib.makeBinPath tools}:$PATH
          exec ${pkgs.treefmt}/bin/treefmt --config-file ${config} "$@"
        ''
      );

      options = lib.genAttrs systems (
        sys:
        let
          pkgs = nixpkgs.legacyPackages.${sys};
          cloudOpts = exampleFlake.nixosConfigurations.nixos-desktop.options.cloud;
        in
        pkgs.writeText "cloud-options.json" (builtins.toJSON (cloud.renderOptions cloudOpts))
      );
    in
    {
      lib = cloud // {
        cloud = bound;
        inherit templates checks options;
      };
      inherit
        templates
        checks
        devShells
        formatter
        options
        ;
    };
}
