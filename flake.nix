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
      dependencyGraph = import ./lib/internal/depgraph.nix { inherit lib; };
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
        nixos.specialArgs = {
          cloudTestArg = "injected";
          cloudNixosOnly = "nixos-only";
        };
        home.specialArgs = {
          cloudTestArg = "injected";
          cloudHomeOnly = "home-only";
        };
        nixpkgs.config.allowUnfree = true;
        nixpkgs.overlays = [
          (final: _: {
            cloud-extra-marker = final.writeText "cloud-extra-marker" "ok";
          })
        ];
        nixos.modules = [
          (
            args@{
              cloudNixosOnly,
              ...
            }:
            {
              assertions = [
                {
                  assertion = !(args ? cloudHomeOnly);
                  message = "home.specialArgs 泄漏到了 NixOS module";
                }
              ];
              environment.sessionVariables.CLOUD_NIXOS_SPECIAL_ARG = cloudNixosOnly;
            }
          )
        ];
        home.modules = [
          (
            args@{
              cloudHomeOnly,
              cloudTestArg,
              pkgs,
              ...
            }:
            {
              home.sessionVariables = {
                CLOUD_SPECIAL_ARG = cloudTestArg;
                CLOUD_HOME_SPECIAL_ARG = cloudHomeOnly;
                CLOUD_NIXOS_SPECIAL_ARG_LEAK = if args ? cloudNixosOnly then "yes" else "no";
                CLOUD_DISCOVERED_OVERLAY = if pkgs ? cloud-example then "yes" else "no";
                CLOUD_EXTRA_OVERLAY = if pkgs ? cloud-extra-marker then "yes" else "no";
                CLOUD_ALLOW_UNFREE = if pkgs.config.allowUnfree then "yes" else "no";
              };
            }
          )
        ];
      };
      # 故意保留扁平参数，验证弃用兼容路径仍然可用
      exampleFlakeNoEmbed = cloud.mkFlake {
        inputs = exampleInputs;
        root = ./examples/basic;
        embedHomeManager = false;
      };

      exampleFlakeHostPolicy = cloud.mkFlake {
        inputs = exampleInputs;
        root = ./examples/basic;
        home.embed = {
          default = true;
          hosts.nixos-desktop = false;
        };
      };
      exampleFlakeDisabled = cloud.mkFlake {
        inputs = exampleInputs;
        root = ./examples/basic;
        outputs.disabled = [
          "apps.hello"
          "checks.example"
          "deploy"
          "formatter"
          "packages.overlay-consumer"
        ];
      };

      exampleFlakeAarch64Only = cloud.mkFlake {
        inputs = exampleInputs;
        root = ./examples/basic;
        systems = [ "aarch64-linux" ];
      };

      exampleFlakeValidated = cloud.mkFlake {
        inputs = exampleInputs;
        root = ./examples/basic;
        systems = [ "x86_64-linux" ];
        outputs = {
          eval = {
            hosts = true;
            homes = true;
          };
          expected = {
            mode = "exact";
            hosts = [
              "hm-standalone"
              "nixos-desktop"
            ];
            homes = [
              "rhencloud"
              "rhencloud@hm-standalone"
              "rhencloud@nixos-desktop"
            ];
            packages.x86_64-linux = [
              "dotted.x86_64-linux"
              "hello"
              "legacy-only"
              "overlay-consumer"
              "system-layout"
            ];
            apps.x86_64-linux = [ "hello" ];
            checks.x86_64-linux = [ "example" ];
            devShells.x86_64-linux = [ "default" ];
            overlays = [ "example" ];
            nixosModules = [
              "_common.always"
              "desktop.example"
              "development.demo"
              "server.demo"
            ];
            homeModules = [ "desktop.example" ];
            formatter = [ "x86_64-linux" ];
            deploy.present = true;
            images = { };
          };
        };
      };

      systems = [
        "x86_64-linux"
        "aarch64-linux"
      ];

      dependencyFixture = metadata: {
        nixos = lib.mapAttrs (_: _: [ ]) metadata;
        home = { };
        meta = lib.mapAttrs (name: value: {
          path = "modules/${name}/meta.nix";
          inherit value;
        }) metadata;
      };
      dependencySuccessChecks =
        let
          orderedGraph = dependencyGraph.buildGraph {
            grouped = dependencyFixture {
              a = { };
              b.after = [ "a" ];
              c.before = [ "b" ];
              d.wants = [ "a" ];
            };
            side = "nixos";
          };
          sideFilteredGraph = dependencyGraph.buildGraph {
            grouped = dependencyFixture {
              a.nixos.enable = false;
              b = { };
            };
            side = "nixos";
          };
          sideDependencyGraph = dependencyGraph.buildGraph {
            grouped = dependencyFixture {
              a = {
                requires = [ "b" ];
                nixos.requires = [ "c" ];
                home.requires = [ "d" ];
              };
              b = { };
              c = { };
              d = { };
            };
            side = "nixos";
          };
          groupGraph = dependencyGraph.buildGraph {
            grouped = dependencyFixture {
              consumer.requiresGroups = [ "desktop-stack" ];
              audio = { };
              portal = { };
            };
            moduleGroups.desktop-stack = [
              "audio"
              "portal"
            ];
            side = "nixos";
          };
          capabilityGraph = dependencyGraph.buildGraph {
            grouped = dependencyFixture {
              consumer.requiresCapabilities = [ "display-server" ];
              wayland.provides = [ "display-server" ];
              xorg.provides = [ "display-server" ];
            };
            side = "nixos";
          };
        in
        {
          stableOrder =
            orderedGraph.order == [
              "a"
              "c"
              "b"
              "d"
            ];
          optionalTargetMayBeAbsent =
            (dependencyGraph.resolve {
              graph = orderedGraph;
              enabled = [
                "b"
                "c"
              ];
              target = "测试夹具";
            }).order == [
              "c"
              "b"
            ];
          sideFiltering = sideFilteredGraph.order == [ "b" ];
          sideDependencies =
            sideDependencyGraph.nodes.a.requires == [
              "b"
              "c"
            ];
          groupExpansion =
            groupGraph.nodes.consumer.requires == [
              "audio"
              "portal"
            ];
          capabilityResolution =
            (dependencyGraph.resolve {
              graph = capabilityGraph;
              enabled = [
                "consumer"
                "wayland"
                "xorg"
              ];
              target = "测试夹具";
            }).order == [
              "wayland"
              "xorg"
              "consumer"
            ];
        };
      dependencyFailureChecks = {
        invalidModuleGroups = builtins.tryEval (
          builtins.deepSeq
            (dependencyGraph.buildGraph {
              grouped = dependencyFixture { };
              moduleGroups = [ ];
              side = "nixos";
            }).order
            true
        );
        emptyGroup = builtins.tryEval (
          builtins.deepSeq
            (dependencyGraph.buildGraph {
              grouped = dependencyFixture { };
              moduleGroups.empty = [ ];
              side = "nixos";
            }).order
            true
        );
        unknownGroup = builtins.tryEval (
          builtins.deepSeq
            (dependencyGraph.buildGraph {
              grouped = dependencyFixture {
                a.requiresGroups = [ "missing" ];
              };
              side = "nixos";
            }).order
            true
        );
        missingCapability =
          let
            graph = dependencyGraph.buildGraph {
              grouped = dependencyFixture {
                a.requiresCapabilities = [ "missing" ];
              };
              side = "nixos";
            };
          in
          builtins.tryEval (
            builtins.deepSeq
              (dependencyGraph.resolve {
                inherit graph;
                enabled = [ "a" ];
                target = "测试夹具";
              }).order
              true
          );
        cycle = builtins.tryEval (
          builtins.deepSeq
            (dependencyGraph.buildGraph {
              grouped = dependencyFixture {
                a.requires = [ "b" ];
                b.requires = [ "a" ];
              };
              side = "nixos";
            }).order
            true
        );
        unknown = builtins.tryEval (
          builtins.deepSeq
            (dependencyGraph.buildGraph {
              grouped = dependencyFixture {
                a.requires = [ "missing" ];
              };
              side = "nixos";
            }).order
            true
        );
        selfReference = builtins.tryEval (
          builtins.deepSeq
            (dependencyGraph.buildGraph {
              grouped = dependencyFixture {
                a.after = [ "a" ];
              };
              side = "nixos";
            }).order
            true
        );
        contradiction = builtins.tryEval (
          builtins.deepSeq
            (dependencyGraph.buildGraph {
              grouped = dependencyFixture {
                a = {
                  requires = [ "b" ];
                  conflicts = [ "b" ];
                };
                b = { };
              };
              side = "nixos";
            }).order
            true
        );
        invalidFieldType = builtins.tryEval (
          builtins.deepSeq
            (dependencyGraph.buildGraph {
              grouped = dependencyFixture {
                a.requires = "b";
              };
              side = "nixos";
            }).order
            true
        );
        missing =
          let
            graph = dependencyGraph.buildGraph {
              grouped = dependencyFixture {
                a.requires = [ "b" ];
                b = { };
              };
              side = "nixos";
            };
          in
          builtins.tryEval (
            builtins.deepSeq
              (dependencyGraph.resolve {
                inherit graph;
                enabled = [ "a" ];
                target = "测试夹具";
              }).order
              true
          );
        conflict =
          let
            graph = dependencyGraph.buildGraph {
              grouped = dependencyFixture {
                a.conflicts = [ "b" ];
                b = { };
              };
              side = "nixos";
            };
          in
          builtins.tryEval (
            builtins.deepSeq
              (dependencyGraph.resolve {
                inherit graph;
                enabled = [
                  "a"
                  "b"
                ];
                target = "测试夹具";
              }).order
              true
          );
      };

      checksFor =
        sys:
        let
          pkgs = nixpkgs.legacyPackages.${sys};
          exampleHost = exampleFlake.nixosConfigurations.nixos-desktop;
          exampleStandaloneHost = exampleFlake.nixosConfigurations.hm-standalone;
          examplePolicyHost = exampleFlakeHostPolicy.nixosConfigurations.nixos-desktop;
          exampleHome = exampleFlake.homeConfigurations."rhencloud@nixos-desktop";
          exampleStandaloneHome = exampleFlake.homeConfigurations."rhencloud@hm-standalone";
          exampleHomeGlobal = exampleFlake.homeConfigurations.rhencloud;
          examplePkg = exampleFlake.packages.${sys}.hello;
          exampleOverlayPkg = exampleFlake.packages.${sys}.overlay-consumer;
          exampleDottedPkg = exampleFlake.packages.${sys}."dotted.x86_64-linux";
          exampleSystemLayoutPkg = exampleFlake.packages.x86_64-linux.system-layout;
          exampleDiscoveredCheck = exampleFlake.checks.${sys}.example;
          exampleDiscoveryReport = exampleFlake.checks.${sys}.cloud-discovery;
          exampleDotGraph = exampleFlake.checks.${sys}.cloud-module-graph-dot;
          validatedChecks = exampleFlakeValidated.checks.x86_64-linux;
          cleanedSource = exampleBound.source.clean {
            root = ./.;
            excludes = [ "docs" ];
          };
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
          exampleSopsCommon = exampleBound.sops.secret { source = "common"; };
          exampleSopsHost = exampleBound.sops.secret {
            source = "host";
            host = "nixos-desktop";
          };
          exampleSopsNamedCommon = exampleBound.sops.secret {
            source = "common";
            name = "password-hash";
          };
          exampleSopsNamedHost = exampleBound.sops.secret {
            source = "host";
            host = "nixos-desktop";
            name = "mihomo-proxies";
          };
          exampleSopsConfig = exampleBound.sops.secret {
            source = "host";
            config.networking.hostName = "nixos-desktop";
          };
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
            test "${exampleHost.config.environment.sessionVariables.CLOUD_NIXOS_SPECIAL_ARG}" = "nixos-only"
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
            test "${exampleEmbeddedHome.home.sessionVariables.CLOUD_HOME_SPECIAL_ARG}" = "home-only"
            test "${exampleEmbeddedHome.home.sessionVariables.CLOUD_NIXOS_SPECIAL_ARG_LEAK}" = "no"
            test "${exampleEmbeddedHome.home.sessionVariables.CLOUD_DISCOVERED_OVERLAY}" = "yes"
            test "${exampleEmbeddedHome.home.sessionVariables.CLOUD_EXTRA_OVERLAY}" = "yes"
            printf '%s\n' "${exampleEmbeddedHome.home.username}" > "$out"
          '';
          homeStandalonePkgs = pkgs.runCommand "cloud-home-standalone-pkgs" { } ''
            test "${exampleHome.config.home.sessionVariables.CLOUD_HOME_SPECIAL_ARG}" = "home-only"
            test "${exampleHome.config.home.sessionVariables.CLOUD_NIXOS_SPECIAL_ARG_LEAK}" = "no"
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
          homeHostPolicies = pkgs.runCommand "cloud-home-host-policies" { } ''
            test "${if exampleHost.config.home-manager.useGlobalPkgs then "yes" else "no"}" = "no"
            if [ "${
              if builtins.hasAttr "home-manager" exampleStandaloneHost.options then "yes" else "no"
            }" = "yes" ]; then
              echo "host meta 禁用嵌入后仍注入了 home-manager 模块" >&2
              exit 1
            fi
            if [ "${
              if builtins.hasAttr "home-manager" examplePolicyHost.options then "yes" else "no"
            }" = "yes" ]; then
              echo "per-host home.embed 策略未生效" >&2
              exit 1
            fi
            test "${exampleStandaloneHome.config.home.sessionVariables.CLOUD_STANDALONE}" = "1"
            printf '%s\n' "${exampleStandaloneHome.config.home.username}" > "$out"
          '';
          package = pkgs.runCommand "cloud-package" { } ''
            test "$(cat ${exampleOverlayPkg})" = "overlay-ok"
            printf '%s\n' "${examplePkg.name}" > "$out"
          '';
          outputcontrol = pkgs.runCommand "cloud-output-control" { } ''
            test -n "${exampleDottedPkg.drvPath}"
            test -n "${exampleDiscoveredCheck.drvPath}"
            if [ "${
              if builtins.hasAttr "disabled-by-meta" exampleFlake.packages.${sys} then "yes" else "no"
            }" = "yes" ]; then
              echo "meta.enable = false 的 package 仍被输出" >&2
              exit 1
            fi
            if [ "${if sys == "x86_64-linux" then "yes" else "no"}" = "yes" ]; then
              test -n "${exampleSystemLayoutPkg.drvPath}"
              test -n "${exampleFlake.packages.${sys}.legacy-only.drvPath}"
            elif [ "${
              if builtins.hasAttr "system-layout" exampleFlake.packages.${sys} then "yes" else "no"
            }" = "yes" ]; then
              echo "system-first package 出现在错误架构" >&2
              exit 1
            elif [ "${
              if builtins.hasAttr "legacy-only" exampleFlake.packages.${sys} then "yes" else "no"
            }" = "yes" ]; then
              echo "旧式 system 后缀 package 出现在错误架构" >&2
              exit 1
            fi
            if [ "${
              if builtins.hasAttr "legacy-only.x86_64-linux" exampleFlakeAarch64Only.packages.aarch64-linux then
                "yes"
              else
                "no"
            }" = "yes" ]; then
              echo "未启用的旧式 system 后缀被误识别为完整包名" >&2
              exit 1
            fi
            if [ "${
              if builtins.hasAttr "overlay-consumer" exampleFlakeDisabled.packages.${sys} then "yes" else "no"
            }" = "yes" ]; then
              echo "outputs.disabled 未禁用 package" >&2
              exit 1
            fi
            if [ "${
              if builtins.hasAttr "example" exampleFlakeDisabled.checks.${sys} then "yes" else "no"
            }" = "yes" ]; then
              echo "outputs.disabled 未禁用 check" >&2
              exit 1
            fi
            if [ "${
              if
                builtins.hasAttr "apps" exampleFlakeDisabled
                && builtins.hasAttr "hello" exampleFlakeDisabled.apps.${sys}
              then
                "yes"
              else
                "no"
            }" = "yes" ]; then
              echo "outputs.disabled 未禁用 app" >&2
              exit 1
            fi
            if [ "${if builtins.hasAttr "formatter" exampleFlakeDisabled then "yes" else "no"}" = "yes" ]; then
              echo "outputs.disabled 未禁用 formatter" >&2
              exit 1
            fi
            if [ "${if builtins.hasAttr "deploy" exampleFlakeDisabled then "yes" else "no"}" = "yes" ]; then
              echo "outputs.disabled 未禁用 deploy" >&2
              exit 1
            fi
            printf '%s\n' "${exampleDottedPkg.name}" > "$out"
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
          modulegraph = pkgs.runCommand "cloud-module-graph" { nativeBuildInputs = [ pkgs.jq ]; } ''
            report=${exampleDiscoveryReport}
            ${pkgs.jq}/bin/jq -e '
              (.moduleGraph.nixos.order | index("development.demo"))
              < (.moduleGraph.nixos.order | index("desktop.example"))
            ' "$report" >/dev/null
            ${pkgs.jq}/bin/jq -e '
              .moduleGraph.nixos.edges
              | any(.from == "development.demo" and .to == "_common.always" and .kind == "requires")
            ' "$report" >/dev/null
            ${pkgs.jq}/bin/jq -e '
              .perHost."nixos-desktop".nixos.enabled
              | index("development.demo") != null
            ' "$report" >/dev/null
            if [ "${
              if lib.all (result: result) (builtins.attrValues dependencySuccessChecks) then "yes" else "no"
            }" != "yes" ]; then
              echo "模块依赖正例未按预期解析" >&2
              exit 1
            fi
            if [ "${
              if lib.all (result: !result.success) (builtins.attrValues dependencyFailureChecks) then
                "yes"
              else
                "no"
            }" != "yes" ]; then
              echo "模块依赖负例未按预期失败" >&2
              exit 1
            fi
            cp "$report" "$out"
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
          newfeatures = pkgs.runCommand "cloud-new-features" { } ''
            test -e ${validatedChecks.cloud-discovery-expected-hosts}
            test -e ${validatedChecks.cloud-discovery-expected-packages}
            test -e ${validatedChecks.cloud-discovery-expected-deploy}
            test -e ${validatedChecks.cloud-eval-hosts}
            test -e ${validatedChecks.cloud-eval-homes}
            test -e ${exampleDotGraph}/nixos.dot
            test -e ${exampleDotGraph}/hosts/nixos-desktop/home.dot
            test ! -e ${cleanedSource}/docs
            test -e ${cleanedSource}/lib/default.nix
            printf '%s\n' ok > "$out"
          '';
          sops = pkgs.runCommand "cloud-sops" { } ''
            test "${exampleSopsModule.sops.defaultSopsFile}" = "${toString ./examples/basic}/secrets/hosts/nixos-desktop.yaml"
            test "${exampleSopsCommon.sopsFile}" = "${toString ./examples/basic}/secrets/common.yaml"
            test "${exampleSopsHost.sopsFile}" = "${toString ./examples/basic}/secrets/hosts/nixos-desktop.yaml"
            test "${exampleSopsNamedCommon.sops.secrets.password-hash.sopsFile}" = "${toString ./examples/basic}/secrets/common.yaml"
            test "${exampleSopsNamedHost.sops.secrets.mihomo-proxies.sopsFile}" = "${toString ./examples/basic}/secrets/hosts/nixos-desktop.yaml"
            test "${exampleSopsConfig.sopsFile}" = "${toString ./examples/basic}/secrets/hosts/nixos-desktop.yaml"
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
