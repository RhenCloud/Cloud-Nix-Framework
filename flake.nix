{
  description = "Snowveil: A Nix Flakes-based configuration framework";

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
      snowveil = import ./lib { inherit lib; };
      schema = import ./lib/schema.nix { };
      dependencyGraph = import ./lib/internal/depgraph.nix { inherit lib; };
      profileTools = import ./lib/internal/profiles.nix { inherit lib; };
      frameworkInputs = {
        inherit self nixpkgs home-manager;
      };
      bound = snowveil.mkLib { inputs = frameworkInputs; };

      templates = {
        default = {
          path = ./templates/default;
          description = "Snowveil minimal working template";
        };
      };

      exampleInputs = {
        inherit nixpkgs home-manager;
        self = {
          outPath = ./examples/basic;
        };
      };
      exampleBound = snowveil.mkLib { inputs = exampleInputs; };
      exampleFlake = snowveil.mkFlake {
        inputs = exampleInputs;
        root = ./examples/basic;
        outputs.diagnostics.perHostModuleGraph = true;
        nixos.specialArgs = {
          snowveilTestArg = "injected";
          snowveilNixosOnly = "nixos-only";
        };
        home.specialArgs = {
          snowveilTestArg = "injected";
          snowveilHomeOnly = "home-only";
        };
        nixpkgs.config.allowUnfree = true;
        nixpkgs.overlays = [
          (final: _: {
            snowveil-extra-marker = final.writeText "snowveil-extra-marker" "ok";
          })
        ];
        nixos.modules = [
          (
            args@{
              snowveilNixosOnly,
              ...
            }:
            {
              assertions = [
                {
                  assertion = !(args ? snowveilHomeOnly);
                  message = "home.specialArgs leaked into NixOS module";
                }
              ];
              environment.sessionVariables.SNOWVEIL_NIXOS_SPECIAL_ARG = snowveilNixosOnly;
            }
          )
        ];
        home.modules = [
          (
            args@{
              snowveilHomeOnly,
              snowveilTestArg,
              pkgs,
              ...
            }:
            {
              home.sessionVariables = {
                SNOWVEIL_SPECIAL_ARG = snowveilTestArg;
                SNOWVEIL_HOME_SPECIAL_ARG = snowveilHomeOnly;
                SNOWVEIL_NIXOS_SPECIAL_ARG_LEAK = if args ? snowveilNixosOnly then "yes" else "no";
                SNOWVEIL_DISCOVERED_OVERLAY = if pkgs ? snowveil-example then "yes" else "no";
                SNOWVEIL_EXTRA_OVERLAY = if pkgs ? snowveil-extra-marker then "yes" else "no";
                SNOWVEIL_ALLOW_UNFREE = if pkgs.config.allowUnfree then "yes" else "no";
              };
            }
          )
        ];
      };
      # 故意保留扁平参数，验证弃用兼容路径仍然可用
      exampleFlakeNoEmbed = snowveil.mkFlake {
        inputs = exampleInputs;
        root = ./examples/basic;
        embedHomeManager = false;
      };

      exampleFlakeHostPolicy = snowveil.mkFlake {
        inputs = exampleInputs;
        root = ./examples/basic;
        home.embed = {
          default = true;
          hosts.nixos-desktop = false;
        };
      };
      exampleFlakeDisabled = snowveil.mkFlake {
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

      exampleFlakeAarch64Only = snowveil.mkFlake {
        inputs = exampleInputs;
        root = ./examples/basic;
        systems = [ "aarch64-linux" ];
      };

      exampleFlakeSelective = snowveil.mkFlake {
        inputs = exampleInputs;
        root = ./examples/basic;
        systems = [ "x86_64-linux" ];
        outputs = {
          eval = {
            hosts = [ "hm-standalone" ];
            homes = [ "rhencloud@hm-standalone" ];
          };
          diagnostics = {
            discovery = false;
            moduleGraph = true;
            perHostModuleGraph = false;
          };
        };
      };

      exampleFlakeNoDiagnostics = snowveil.mkFlake {
        inputs = exampleInputs;
        root = ./examples/basic;
        systems = [ "x86_64-linux" ];
        outputs.diagnostics = {
          discovery = false;
          moduleGraph = false;
          perHostModuleGraph = false;
        };
      };

      invalidOutputCheck =
        outputs:
        let
          result = snowveil.mkFlake {
            inputs = exampleInputs;
            root = ./examples/basic;
            systems = [ "x86_64-linux" ];
            inherit outputs;
          };
        in
        builtins.tryEval (builtins.deepSeq (builtins.attrNames result.checks.x86_64-linux) true);

      invalidOutputChecks = {
        evalUnknown = invalidOutputCheck {
          eval.hosts = [ "missing-host" ];
        };
        evalType = invalidOutputCheck {
          eval.homes = "rhencloud";
        };
        diagnosticsType = invalidOutputCheck {
          diagnostics.discovery = "yes";
        };
      };

      exampleFlakeValidated = snowveil.mkFlake {
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

      exampleFlakeHomesStandaloneDisabled = snowveil.mkFlake {
        inputs = exampleInputs;
        root = ./examples/basic;
        outputs.homes.standalone = false;
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
              target = "test fixture";
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
              target = "test fixture";
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
                target = "test fixture";
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
                target = "test fixture";
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
                target = "test fixture";
              }).order
              true
          );
      };

      profileSuccessChecks = {
        listFormBothSides =
          profileTools.readProfile {
            name = "workstation";
            value = [
              "a"
              "b"
            ];
            source = "test fixture";
          } == {
            nixos = [
              "a"
              "b"
            ];
            home = [
              "a"
              "b"
            ];
          };
        attrsetFormScoping =
          profileTools.readProfile {
            name = "workstation";
            value = {
              common = [ "a" ];
              nixos = [ "b" ];
            };
            source = "test fixture";
          } == {
            nixos = [
              "a"
              "b"
            ];
            home = [ "a" ];
          };
        knownMembersPass =
          profileTools.checkMembers {
            profile = "workstation";
            source = "test fixture";
            side = "nixos";
            members = [ "a" ];
            knownNames = [
              "a"
              "b"
            ];
          } == [ "a" ];
        knownHostProfilesPass =
          profileTools.checkHostProfiles {
            host = "testbox";
            declared = [ "workstation" ];
            knownProfiles.workstation = { };
          } == [ "workstation" ];
      };

      profileFailureChecks = {
        invalidShape = builtins.tryEval (
          profileTools.readProfile {
            name = "workstation";
            value = 1;
            source = "test fixture";
          }
        );
        emptyList = builtins.tryEval (
          profileTools.readProfile {
            name = "workstation";
            value = [ ];
            source = "test fixture";
          }
        );
        emptyAttrset = builtins.tryEval (
          profileTools.readProfile {
            name = "workstation";
            value = { };
            source = "test fixture";
          }
        );
        unknownField = builtins.tryEval (
          profileTools.readProfile {
            name = "workstation";
            value.bogus = [ "a" ];
            source = "test fixture";
          }
        );
        nonStringMember = builtins.tryEval (
          profileTools.readProfile {
            name = "workstation";
            value = [ 1 ];
            source = "test fixture";
          }
        );
        unknownMember = builtins.tryEval (
          profileTools.checkMembers {
            profile = "workstation";
            source = "test fixture";
            side = "nixos";
            members = [ "missing" ];
            knownNames = [ "a" ];
          }
        );
        unknownHostProfile = builtins.tryEval (
          profileTools.checkHostProfiles {
            host = "testbox";
            declared = [ "missing" ];
            knownProfiles.workstation = { };
          }
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
          exampleDiscoveryReport = exampleFlake.checks.${sys}.snowveil-discovery;
          exampleDotGraph = exampleFlake.checks.${sys}.snowveil-module-graph-dot;
          validatedChecks = exampleFlakeValidated.checks.x86_64-linux;
          selectiveChecks = exampleFlakeSelective.checks.x86_64-linux;
          noDiagnosticChecks = exampleFlakeNoDiagnostics.checks.x86_64-linux;
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
            snowveil = self;
          };
        in
        {
          surface = pkgs.runCommand "snowveil-surface" { } ''
            printf '%s\n' "${builtins.concatStringsSep " " (builtins.attrNames snowveil)}" > "$out"
          '';
          host = pkgs.runCommand "snowveil-host" { } ''
            test "${exampleHost.config.environment.sessionVariables.SNOWVEIL_NIXOS_SPECIAL_ARG}" = "nixos-only"
            printf '%s\n' "${toString exampleHost.config.snowveil.users}" > "$out"
          '';
          users = pkgs.runCommand "snowveil-users" { } ''
            test "${toString exampleHost.config.users.users.rhencloud.isNormalUser}" = "1"
            test "${exampleHost.config.users.users.rhencloud.home}" = "/home/rhencloud"
            test "${exampleHost.config.users.users.rhencloud.group}" = "rhencloud"
            test "${toString exampleHost.config.users.users.rhencloud.uid}" = "1000"
            test "${toString exampleHost.config.users.groups.rhencloud.gid}" = "1000"
            test "${toString exampleHost.config.users.users.rhencloud.extraGroups}" = "wheel"
            test "${exampleStandaloneHost.config.users.users.rhencloud.group}" = "rhencloud"
            printf '%s\n' "${toString exampleHost.config.users.users.rhencloud.uid}" > "$out"
          '';
          home = pkgs.runCommand "snowveil-home" { } ''
            printf '%s\n' "${exampleHome.config.home.username}" > "$out"
          '';
          homeGlobal = pkgs.runCommand "snowveil-home-global" { } ''
            printf '%s\n' "${exampleHomeGlobal.config.home.username}" > "$out"
          '';
          homeEmbedded = pkgs.runCommand "snowveil-home-embedded" { } ''
            test "${exampleEmbeddedHome.home.username}" = "rhencloud"
            test "${exampleEmbeddedHome.home.sessionVariables.SNOWVEIL_SPECIAL_ARG}" = "injected"
            test "${exampleEmbeddedHome.home.sessionVariables.SNOWVEIL_HOME_SPECIAL_ARG}" = "home-only"
            test "${exampleEmbeddedHome.home.sessionVariables.SNOWVEIL_NIXOS_SPECIAL_ARG_LEAK}" = "no"
            test "${exampleEmbeddedHome.home.sessionVariables.SNOWVEIL_DISCOVERED_OVERLAY}" = "yes"
            test "${exampleEmbeddedHome.home.sessionVariables.SNOWVEIL_EXTRA_OVERLAY}" = "yes"
            printf '%s\n' "${exampleEmbeddedHome.home.username}" > "$out"
          '';
          homeStandalonePkgs = pkgs.runCommand "snowveil-home-standalone-pkgs" { } ''
            test "${exampleHome.config.home.sessionVariables.SNOWVEIL_HOME_SPECIAL_ARG}" = "home-only"
            test "${exampleHome.config.home.sessionVariables.SNOWVEIL_NIXOS_SPECIAL_ARG_LEAK}" = "no"
            test "${exampleHome.config.home.sessionVariables.SNOWVEIL_DISCOVERED_OVERLAY}" = "yes"
            test "${exampleHome.config.home.sessionVariables.SNOWVEIL_EXTRA_OVERLAY}" = "yes"
            test "${exampleHome.config.home.sessionVariables.SNOWVEIL_ALLOW_UNFREE}" = "yes"
            printf '%s\n' "${exampleHome.config.home.username}" > "$out"
          '';
          homeNoEmbed = pkgs.runCommand "snowveil-home-no-embed" { } ''
            if [ "${
              if builtins.hasAttr "home-manager" exampleNoEmbedHost.options then "yes" else "no"
            }" = "yes" ]; then
              echo "home-manager module still injected when embedHomeManager = false" >&2
              exit 1
            fi
            printf '%s\n' "${exampleNoEmbedHome.config.home.username}" > "$out"
          '';
          homeHostPolicies = pkgs.runCommand "snowveil-home-host-policies" { } ''
            test "${if exampleHost.config.home-manager.useGlobalPkgs then "yes" else "no"}" = "no"
            if [ "${
              if builtins.hasAttr "home-manager" exampleStandaloneHost.options then "yes" else "no"
            }" = "yes" ]; then
              echo "home-manager module still injected after host meta disabled embed" >&2
              exit 1
            fi
            if [ "${
              if builtins.hasAttr "home-manager" examplePolicyHost.options then "yes" else "no"
            }" = "yes" ]; then
              echo "per-host home.embed policy did not take effect" >&2
              exit 1
            fi
            test "${exampleStandaloneHome.config.home.sessionVariables.SNOWVEIL_STANDALONE}" = "1"
            printf '%s\n' "${exampleStandaloneHome.config.home.username}" > "$out"
          '';
          package = pkgs.runCommand "snowveil-package" { } ''
            test "$(cat ${exampleOverlayPkg})" = "overlay-ok"
            printf '%s\n' "${examplePkg.name}" > "$out"
          '';
          outputcontrol = pkgs.runCommand "snowveil-output-control" { } ''
            test "${if lib.isDerivation exampleDottedPkg then "yes" else "no"}" = "yes"
            test "${if lib.isDerivation exampleDiscoveredCheck then "yes" else "no"}" = "yes"
            if [ "${
              if builtins.hasAttr "disabled-by-meta" exampleFlake.packages.${sys} then "yes" else "no"
            }" = "yes" ]; then
              echo "package with meta.enable = false was still exported" >&2
              exit 1
            fi
            if [ "${if sys == "x86_64-linux" then "yes" else "no"}" = "yes" ]; then
              test "${
                if sys == "x86_64-linux" && lib.isDerivation exampleSystemLayoutPkg then "yes" else "no"
              }" = "yes"
              test "${
                if sys == "x86_64-linux" && lib.isDerivation exampleFlake.packages.${sys}.legacy-only then
                  "yes"
                else
                  "no"
              }" = "yes"
            elif [ "${
              if builtins.hasAttr "system-layout" exampleFlake.packages.${sys} then "yes" else "no"
            }" = "yes" ]; then
              echo "system-first package appeared under the wrong architecture" >&2
              exit 1
            elif [ "${
              if builtins.hasAttr "legacy-only" exampleFlake.packages.${sys} then "yes" else "no"
            }" = "yes" ]; then
              echo "legacy system-suffixed package appeared under the wrong architecture" >&2
              exit 1
            fi
            if [ "${
              if builtins.hasAttr "legacy-only.x86_64-linux" exampleFlakeAarch64Only.packages.aarch64-linux then
                "yes"
              else
                "no"
            }" = "yes" ]; then
              echo "unactivated legacy system suffix was misidentified as a full package name" >&2
              exit 1
            fi
            if [ "${
              if builtins.hasAttr "overlay-consumer" exampleFlakeDisabled.packages.${sys} then "yes" else "no"
            }" = "yes" ]; then
              echo "outputs.disabled did not disable package" >&2
              exit 1
            fi
            if [ "${
              if builtins.hasAttr "example" exampleFlakeDisabled.checks.${sys} then "yes" else "no"
            }" = "yes" ]; then
              echo "outputs.disabled did not disable check" >&2
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
              echo "outputs.disabled did not disable app" >&2
              exit 1
            fi
            if [ "${if builtins.hasAttr "formatter" exampleFlakeDisabled then "yes" else "no"}" = "yes" ]; then
              echo "outputs.disabled did not disable formatter" >&2
              exit 1
            fi
            if [ "${if builtins.hasAttr "deploy" exampleFlakeDisabled then "yes" else "no"}" = "yes" ]; then
              echo "outputs.disabled did not disable deploy" >&2
              exit 1
            fi
            printf '%s\n' "${exampleDottedPkg.name}" > "$out"
          '';
          overlay = pkgs.runCommand "snowveil-overlay" { } ''
            printf '%s\n' "${if builtins.isFunction exampleOverlay then "ok" else "bad"}" > "$out"
          '';
          devshell = pkgs.runCommand "snowveil-devshell" { } ''
            printf '%s\n' "${if exampleDevshell ? name then "ok" else "bad"}" > "$out"
          '';
          userlib = pkgs.runCommand "snowveil-userlib" { } ''
            printf '%s\n' "${exampleLib "hi"}" > "$out"
          '';
          images = pkgs.runCommand "snowveil-images" { } ''
            printf '%s\n' "${toString (builtins.attrNames exampleFlake.images)}" > "$out"
          '';
          modulegraph = pkgs.runCommand "snowveil-module-graph" { nativeBuildInputs = [ pkgs.jq ]; } ''
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
              echo "module dependency success cases did not resolve as expected" >&2
              exit 1
            fi
            if [ "${
              if lib.all (result: !result.success) (builtins.attrValues dependencyFailureChecks) then
                "yes"
              else
                "no"
            }" != "yes" ]; then
              echo "module dependency failure cases did not fail as expected" >&2
              exit 1
            fi
            cp "$report" "$out"
          '';
          rolefilter = pkgs.runCommand "snowveil-rolefilter" { } ''

            if [ -n "${exampleHost.config.environment.variables.SNOWVEIL_SERVER or ""}" ]; then
              echo "server role module should have been filtered out, but was not" >&2
              exit 1
            fi
            if [ -z "${exampleHost.config.environment.variables.SNOWVEIL_COMMON or ""}" ]; then
              echo "_common shared module should always be injected, but was not" >&2
              exit 1
            fi
            if [ -z "${exampleHost.config.environment.variables.SNOWVEIL_DEVELOPMENT or ""}" ]; then
              echo "development composite-role module should be injected, but was not" >&2
              exit 1
            fi
            test "${exampleHost.config.environment.variables.SNOWVEIL_HOST_CONFIG_ARG}" = "nixos-desktop"
            printf '%s\n' "${exampleHost.config.environment.variables.SNOWVEIL_EXAMPLE}" > "$out"
          '';
          hostfragments = pkgs.runCommand "snowveil-host-fragments" { nativeBuildInputs = [ pkgs.jq ]; } ''
            test "${exampleHost.config.environment.variables.SNOWVEIL_HOST_HARDWARE}" = "1"
            test "${exampleHost.config.environment.variables.SNOWVEIL_HOST_DISK}" = "1"
            test "${exampleHost.config.networking.hostName}" = "nixos-desktop"
            report=${exampleDiscoveryReport}
            ${pkgs.jq}/bin/jq -e '.hostFiles."nixos-desktop" == ["default.nix","hardware.nix","disk.nix","network.nix"]' "$report" >/dev/null
            ${pkgs.jq}/bin/jq -e '.hostFiles."hm-standalone" == ["default.nix"]' "$report" >/dev/null
            if [ -n "${exampleStandaloneHost.config.environment.variables.SNOWVEIL_HOST_HARDWARE or ""}" ]; then
              echo "hm-standalone did not declare hardware.nix, yet the fragment leaked into that host" >&2
              exit 1
            fi
            printf '%s\n' ok > "$out"
          '';
          profiles = pkgs.runCommand "snowveil-profiles" { nativeBuildInputs = [ pkgs.jq ]; } ''
            test "${exampleHost.config.environment.variables.SNOWVEIL_PROFILE_PODMAN}" = "1"
            test "${exampleHost.config.environment.variables.SNOWVEIL_PROFILE_GITCONFIG_NIXOS}" = "1"
            test "${exampleHome.config.home.sessionVariables.SNOWVEIL_PROFILE_GITCONFIG}" = "1"
            if [ -n "${
              exampleStandaloneHost.config.environment.variables.SNOWVEIL_PROFILE_PODMAN or ""
            }" ]; then
              echo "modules override should disable profile members, but workstation.podman was still loaded" >&2
              exit 1
            fi
            if [ -n "${
              exampleStandaloneHost.config.environment.variables.SNOWVEIL_PROFILE_GITCONFIG_NIXOS or ""
            }" ]; then
              echo "hm-standalone did not declare the personal profile, yet workstation.gitconfig leaked in" >&2
              exit 1
            fi
            if [ -n "${
              exampleStandaloneHome.config.home.sessionVariables.SNOWVEIL_PROFILE_GITCONFIG or ""
            }" ]; then
              echo "hm-standalone did not declare the personal profile, yet home-side modules leaked in" >&2
              exit 1
            fi
            report=${exampleDiscoveryReport}
            ${pkgs.jq}/bin/jq -e '.discoverySpecVersion == "1.3"' "$report" >/dev/null
            ${pkgs.jq}/bin/jq -e '.profiles.workstation.nixos == ["workstation.podman"]' "$report" >/dev/null
            ${pkgs.jq}/bin/jq -e '.profiles.workstation.home == []' "$report" >/dev/null
            ${pkgs.jq}/bin/jq -e '.profiles.personal.nixos == ["workstation.gitconfig"] and .profiles.personal.home == ["workstation.gitconfig"]' "$report" >/dev/null
            ${pkgs.jq}/bin/jq -e '.hostProfiles."nixos-desktop" == ["workstation","personal"]' "$report" >/dev/null
            ${pkgs.jq}/bin/jq -e '.hostProfiles."hm-standalone" == ["workstation"]' "$report" >/dev/null
            ${pkgs.jq}/bin/jq -e '.perHost."hm-standalone".nixos.disabledReasons."workstation.podman" == "explicitly disabled by host module override"' "$report" >/dev/null
            if [ "${
              if lib.all (result: result) (builtins.attrValues profileSuccessChecks) then "yes" else "no"
            }" != "yes" ]; then
              echo "profile success cases did not resolve as expected" >&2
              exit 1
            fi
            if [ "${
              if lib.all (result: !result.success) (builtins.attrValues profileFailureChecks) then "yes" else "no"
            }" != "yes" ]; then
              echo "profile failure cases did not fail as expected" >&2
              exit 1
            fi
            printf '%s\n' ok > "$out"
          '';
          homesstandalone = pkgs.runCommand "snowveil-homes-standalone" { } ''
            # Default: standalone homes enabled
            test "${
              if builtins.hasAttr "rhencloud" exampleFlake.homeConfigurations then "yes" else "no"
            }" = "yes"
            test "${
              if builtins.hasAttr "rhencloud@nixos-desktop" exampleFlake.homeConfigurations then "yes" else "no"
            }" = "yes"
            # With standalone disabled: only per-host homes
            test "${
              if builtins.hasAttr "rhencloud" exampleFlakeHomesStandaloneDisabled.homeConfigurations then
                "yes"
              else
                "no"
            }" = "no"
            test "${
              if
                builtins.hasAttr "rhencloud@nixos-desktop" exampleFlakeHomesStandaloneDisabled.homeConfigurations
              then
                "yes"
              else
                "no"
            }" = "yes"
            printf '%s\n' ok > "$out"
          '';
          extensions = pkgs.runCommand "snowveil-extensions" { } ''
            test "${exampleApp.type}" = "app"
            test -n "${exampleApp.program}"
            test "${if lib.isDerivation exampleFormatter then "yes" else "no"}" = "yes"
            test "${exampleDeploy.root}" = "${toString ./examples/basic}"
            printf '%s\n' "${exampleApp.program}" > "$out"
          '';
          moduleoutputs = pkgs.runCommand "snowveil-module-outputs" { } ''
            names="${builtins.concatStringsSep " " (builtins.attrNames exampleFlake.nixosModules)}"
            case " $names " in
              *" desktop.example "*) ;;
              *) echo "nixosModules is missing directory-level key desktop.example" >&2; exit 1 ;;
            esac
            case " $names " in
              *" desktop.example.nixos.nix "*) echo "nixosModules still exposes the magic file name" >&2; exit 1 ;;
              *) ;;
            esac
            printf '%s\n' "$names" > "$out"
          '';
          newfeatures = pkgs.runCommand "snowveil-new-features" { } ''
            test -e ${validatedChecks.snowveil-discovery-expected-hosts}
            test -e ${validatedChecks.snowveil-discovery-expected-packages}
            test -e ${validatedChecks.snowveil-discovery-expected-deploy}
            test -e ${validatedChecks.snowveil-eval-hosts}
            test -e ${validatedChecks.snowveil-eval-homes}
            test -e ${exampleDotGraph}/nixos.dot
            test -e ${exampleDotGraph}/hosts/nixos-desktop/home.dot
            test ! -e ${cleanedSource}/docs
            test -e ${cleanedSource}/lib/default.nix
            printf '%s\n' ok > "$out"
          '';
          evalcontrols = pkgs.runCommand "snowveil-eval-controls" { nativeBuildInputs = [ pkgs.jq ]; } ''
            ${pkgs.jq}/bin/jq -e 'map(.name) == ["hm-standalone"]' ${selectiveChecks.snowveil-eval-hosts} >/dev/null
            ${pkgs.jq}/bin/jq -e 'map(.name) == ["rhencloud@hm-standalone"]' ${selectiveChecks.snowveil-eval-homes} >/dev/null
            test -e ${selectiveChecks.snowveil-module-graph-dot}/nixos.dot
            test ! -e ${selectiveChecks.snowveil-module-graph-dot}/hosts
            test "${if builtins.hasAttr "snowveil-discovery" selectiveChecks then "yes" else "no"}" = "no"
            test "${
              if builtins.hasAttr "snowveil-module-graph-dot" noDiagnosticChecks then "yes" else "no"
            }" = "no"
            test "${
              if lib.all (result: !result.success) (builtins.attrValues invalidOutputChecks) then "yes" else "no"
            }" = "yes"
            printf '%s\n' ok > "$out"
          '';
          sops = pkgs.runCommand "snowveil-sops" { } ''
            test "${exampleSopsModule.sops.defaultSopsFile}" = "${toString ./examples/basic}/secrets/hosts/nixos-desktop.yaml"
            test "${exampleSopsCommon.sopsFile}" = "${toString ./examples/basic}/secrets/common.yaml"
            test "${exampleSopsHost.sopsFile}" = "${toString ./examples/basic}/secrets/hosts/nixos-desktop.yaml"
            test "${exampleSopsNamedCommon.sops.secrets.password-hash.sopsFile}" = "${toString ./examples/basic}/secrets/common.yaml"
            test "${exampleSopsNamedHost.sops.secrets.mihomo-proxies.sopsFile}" = "${toString ./examples/basic}/secrets/hosts/nixos-desktop.yaml"
            test "${exampleSopsConfig.sopsFile}" = "${toString ./examples/basic}/secrets/hosts/nixos-desktop.yaml"
            printf '%s\n' "${exampleSopsModule.sops.defaultSopsFile}" > "$out"
          '';
          examplereal = pkgs.runCommand "snowveil-example-real" { } ''
            if [ -z "${toString (builtins.attrNames exampleBasicReal.nixosConfigurations)}" ]; then
              echo "examples/basic entry is wrong: no nixosConfigurations were generated (should be inputs.snowveil.lib.mkFlake)" >&2
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
          snowveilOpts = exampleFlake.nixosConfigurations.nixos-desktop.options.snowveil;
        in
        pkgs.writeText "snowveil-options.json" (builtins.toJSON (snowveil.renderOptions snowveilOpts))
      );

    in
    {
      lib = snowveil // {
        snowveil = bound;
        inherit templates checks options;
      };
      inherit
        templates
        checks
        devShells
        formatter
        options
        ;

      # Framework contract: known flake output schema
      # Reduces "unknown flake output" warnings from Nix tools
      # Defines all standard outputs for Snowveil meta flake and generated user flakes
      flakeOutputsSchema = schema.metaFlakeOutputs // {
        # Note: user flakes will also produce these additional outputs (auto-generated)
        userFlakeOutputsNote = "User flakes will also include: nixosConfigurations, homeConfigurations, packages, apps, nixosModules, homeModules, overlays, images, deploy";
      };
    };
}
