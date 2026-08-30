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
      exampleBound = cloud.mkLib { inputs = exampleInputs; };
      exampleFlake = cloud.mkFlake {
        inputs = exampleInputs;
        root = ./examples/basic;
        extraSpecialArgs.cloudTestArg = "injected";
        nixpkgsConfig.allowUnfree = true;
        extraOverlays = [
          (final: _: {
            cloud-extra-marker = final.writeText "cloud-extra-marker" "ok";
          })
        ];
        extraHomeModules = [
          (
            {
              cloudTestArg,
              pkgs,
              ...
            }:
            {
              home.sessionVariables = {
                CLOUD_SPECIAL_ARG = cloudTestArg;
                CLOUD_DISCOVERED_OVERLAY = if pkgs ? cloud-example then "yes" else "no";
                CLOUD_EXTRA_OVERLAY = if pkgs ? cloud-extra-marker then "yes" else "no";
                CLOUD_ALLOW_UNFREE = if pkgs.config.allowUnfree then "yes" else "no";
              };
            }
          )
        ];
      };
      exampleFlakeNoEmbed = cloud.mkFlake {
        inputs = exampleInputs;
        root = ./examples/basic;
        embedHomeManager = false;
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
          exampleOverlayPkg = exampleFlake.packages.${sys}.overlay-consumer;
          exampleDevshell = exampleFlake.devShells.${sys}.default;
          exampleOverlay = exampleFlake.overlays.example;
          exampleLib = exampleFlake.lib.example.shout;
          exampleEmbeddedHome = exampleHost.config.home-manager.users.rhencloud;
          exampleNoEmbedHost = exampleFlakeNoEmbed.nixosConfigurations.nixos-desktop;
          exampleNoEmbedHome = exampleFlakeNoEmbed.homeConfigurations."rhencloud@nixos-desktop";
          exampleApp = exampleFlake.apps.${sys}.hello;
          exampleFormatter = exampleFlake.formatter.${sys};
          exampleDeploy = exampleFlake.deploy;
          exampleSopsModule =
            (exampleBound.sops.mkModule {
              sopsNixModule = { };
              host = "nixos-desktop";
            })
              { };
          exampleBasicReal = (import ./examples/basic/flake.nix).outputs {
            self = {
              outPath = ./examples/basic;
            };
            inherit nixpkgs home-manager;
            cloud = self;
          };
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
          homeEmbedded = pkgs.runCommand "cloud-home-embedded" { } ''
            test "${exampleEmbeddedHome.home.username}" = "rhencloud"
            test "${exampleEmbeddedHome.home.sessionVariables.CLOUD_SPECIAL_ARG}" = "injected"
            test "${exampleEmbeddedHome.home.sessionVariables.CLOUD_DISCOVERED_OVERLAY}" = "yes"
            test "${exampleEmbeddedHome.home.sessionVariables.CLOUD_EXTRA_OVERLAY}" = "yes"
            printf '%s\n' "${exampleEmbeddedHome.home.username}" > "$out"
          '';
          homeStandalonePkgs = pkgs.runCommand "cloud-home-standalone-pkgs" { } ''
            test "${exampleHome.config.home.sessionVariables.CLOUD_DISCOVERED_OVERLAY}" = "yes"
            test "${exampleHome.config.home.sessionVariables.CLOUD_EXTRA_OVERLAY}" = "yes"
            test "${exampleHome.config.home.sessionVariables.CLOUD_ALLOW_UNFREE}" = "yes"
            printf '%s\n' "${exampleHome.config.home.username}" > "$out"
          '';
          homeNoEmbed = pkgs.runCommand "cloud-home-no-embed" { } ''
            if [ "${
              if builtins.hasAttr "home-manager" exampleNoEmbedHost.options then "yes" else "no"
            }" = "yes" ]; then
              echo "embedHomeManager = false 时仍注入了 home-manager 模块" >&2
              exit 1
            fi
            printf '%s\n' "${exampleNoEmbedHome.config.home.username}" > "$out"
          '';
          package = pkgs.runCommand "cloud-package" { } ''
            test "$(cat ${exampleOverlayPkg})" = "overlay-ok"
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
            if [ -z "${exampleHost.config.environment.variables.CLOUD_COMMON or ""}" ]; then
              echo "_common 共享模块应始终注入，但未" >&2
              exit 1
            fi
            if [ -z "${exampleHost.config.environment.variables.CLOUD_DEVELOPMENT or ""}" ]; then
              echo "development 组合角色模块应注入，但未" >&2
              exit 1
            fi
            test "${exampleHost.config.environment.variables.CLOUD_HOST_CONFIG_ARG}" = "nixos-desktop"
            printf '%s\n' "${exampleHost.config.environment.variables.CLOUD_EXAMPLE}" > "$out"
          '';
          extensions = pkgs.runCommand "cloud-extensions" { } ''
            test "${exampleApp.type}" = "app"
            test -n "${exampleApp.program}"
            test -n "${exampleFormatter.drvPath}"
            test "${exampleDeploy.root}" = "${toString ./examples/basic}"
            printf '%s\n' "${exampleApp.program}" > "$out"
          '';
          moduleoutputs = pkgs.runCommand "cloud-module-outputs" { } ''
            names="${builtins.concatStringsSep " " (builtins.attrNames exampleFlake.nixosModules)}"
            case " $names " in
              *" desktop.example "*) ;;
              *) echo "nixosModules 缺少目录级键 desktop.example" >&2; exit 1 ;;
            esac
            case " $names " in
              *" desktop.example.nixos.nix "*) echo "nixosModules 仍暴露 magic 文件名" >&2; exit 1 ;;
              *) ;;
            esac
            printf '%s\n' "$names" > "$out"
          '';
          sops = pkgs.runCommand "cloud-sops" { } ''
            test "${exampleSopsModule.sops.defaultSopsFile}" = "${toString ./examples/basic}/secrets/hosts/nixos-desktop.yaml"
            printf '%s\n' "${exampleSopsModule.sops.defaultSopsFile}" > "$out"
          '';
          examplereal = pkgs.runCommand "cloud-example-real" { } ''
            if [ -z "${toString (builtins.attrNames exampleBasicReal.nixosConfigurations)}" ]; then
              echo "examples/basic 入口错误：未生成 nixosConfigurations（应为 inputs.cloud.lib.mkFlake）" >&2
              exit 1
            fi
            printf '%s\n' "${toString (builtins.attrNames exampleBasicReal.nixosConfigurations)}" > "$out"
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
