{ lib }:

# Snowveil - 库入口
# 结构：
#   ./discover.nix  - 目录自动发现
#   ./host.nix      - 主机元数据
#   ./sops.nix      - SOPS 密钥管理
#   ./patches.nix   - Patch 帮助函数
#   ./fs.nix        - 文件系统遍历
#   ./internal/     - 框架内部模块

let
  fs = import ./fs.nix { inherit lib; };
  patches = import ./patches.nix;
  sourceTools = import ./source.nix { inherit lib; };
  moduleTools = import ./internal/modules.nix { inherit lib; };
  depGraph = import ./internal/depgraph.nix { inherit lib; };
  profileTools = import ./internal/profiles.nix { inherit lib; };
  userTools = import ./user.nix { inherit lib; };
  utils = import ./internal/utils.nix { inherit lib; };
  builtinOptions = import ./internal/options.nix { };

  inherit (utils) renderOptions;
  inherit (builtinOptions) optionsSnowveil optionsSnowveilHome;

  defaultSystems = [
    "x86_64-linux"
    "aarch64-linux"
  ];

  forAllSystems = systems: f: lib.genAttrs systems f;
  sortNames = lib.sort (a: b: a < b);

  version = {
    major = 0;
    minor = 5;
    patch = 0;
    pre = "dev";
    string = "0.5.0-dev";
  };

  bind =
    {
      inputs,
      moduleRegistries ? [ ],
      moduleGroups ? { },
      profiles ? { },
      root ? null,
    }:
    let
      self =
        inputs.self
          or (throw "error: missing required flake input

  Snowveil requires inputs.self
  make sure 'self' is included in your flake inputs");
      nixpkgs =
        inputs.nixpkgs
          or (throw "error: missing required flake input

  Snowveil requires inputs.nixpkgs
  make sure 'nixpkgs' is included in your flake inputs");
      nixosSystem = nixpkgs.lib.nixosSystem;
      hm = inputs.home-manager or null;
      projectRoot = if root == null then toString self.outPath else toString root;
      channels = { inherit nixpkgs; };

      discovered = import ./discover.nix {
        inherit
          lib
          fs
          projectRoot
          moduleRegistries
          moduleGroups
          profiles
          ;
      };

      hostMeta = import ./host.nix {
        inherit lib discovered;
      };

      sops' = import ./sops.nix { inherit projectRoot; };
      source = sourceTools // {
        clean = args: sourceTools.clean ({ root = projectRoot; } // args);
      };
      projectSource = source.clean { };
      snowveilInject = {
        inherit
          patches
          version
          source
          projectSource
          ;
        sops = sops';
      };
      snowveil = snowveilInject;

      # overlays: 支持两种签名
      #   final: prev: { ... }                      标准 nixpkgs overlay
      #   { inputs, self, snowveil }: final: prev: ... 带框架参数的解构签名
      loadOverlay =
        path:
        let
          imported = import path;
          argNames = builtins.functionArgs imported;
          isStructured = argNames ? inputs || argNames ? self || argNames ? snowveil;
        in
        if isStructured then imported { inherit inputs self snowveil; } else imported;

      overlays = lib.listToAttrs (
        map (o: lib.nameValuePair o.name (loadOverlay o.path)) discovered.overlays
      );
      overlayList = lib.attrValues overlays;

      pkgsFor =
        {
          system,
          nixpkgsConfig ? { },
          extraOverlays ? [ ],
        }:
        if
          nixpkgsConfig == { }
          && overlayList == [ ]
          && extraOverlays == [ ]
          && builtins.hasAttr system (nixpkgs.legacyPackages or { })
        then
          nixpkgs.legacyPackages.${system}
        else
          import nixpkgs {
            inherit system;
            config = nixpkgsConfig;
            overlays = overlayList ++ extraOverlays;
          };

      importFile =
        path:
        let
          imported = import path;
          declared = if builtins.isFunction imported then builtins.functionArgs imported else { };
          args = builtins.intersectAttrs declared {
            inherit
              lib
              inputs
              self
              snowveil
              ;
          };
        in
        if builtins.isFunction imported then imported args else imported;

      callPackage =
        pkgs: path:
        let
          fn = import path;
          declared = builtins.functionArgs fn;
          extras = lib.intersectAttrs declared { inherit inputs self snowveil; };
        in
        pkgs.callPackage fn extras;

      specialArgsFor =
        extraSpecialArgs:
        {
          inherit
            inputs
            self
            channels
            snowveil
            ;
        }
        // extraSpecialArgs;

      usersForHost = host: discovered.usersByHost.${host} or [ ];

      selectLocalModules =
        {
          side,
          roles,
          overrideMap,
          profileEnabled ? [ ],
          target,
        }:
        let
          graph = discovered.moduleGraph.${side};
          moduleIndex = discovered.localGroupedModules.index;
          sideOnly = if side == "nixos" then "nixosOnly" else "homeOnly";
          rolesSet = if roles == null then null else lib.genAttrs roles (_: true);
          profileSet = lib.genAttrs profileEnabled (_: true);
          selectedByName = lib.mapAttrs (
            name: node:
            let
              record = moduleIndex.${name};
              roleMatches = record.common || rolesSet == null || builtins.hasAttr record.role rolesSet;
              defaultPaths = record.shared ++ lib.optionals roleMatches record.${sideOnly};
              override = overrideMap.${name} or null;
            in
            if override == false then
              [ ]
            else if override == true || builtins.hasAttr name profileSet then
              node.paths
            else
              defaultPaths
          ) graph.nodes;
          allNames = builtins.attrNames selectedByName;
          enabled = lib.filter (name: selectedByName.${name} != [ ]) allNames;
          enabledSet = lib.genAttrs enabled (_: true);
          disabled = lib.filter (name: !builtins.hasAttr name enabledSet) allNames;
          disabledReasons = builtins.listToAttrs (
            map (
              name:
              lib.nameValuePair name (
                if (overrideMap.${name} or null) == false then
                  "explicitly disabled by host module override"
                else
                  "not selected by role filter"
              )
            ) disabled
          );
          resolved = depGraph.resolve {
            inherit
              graph
              enabled
              target
              disabledReasons
              ;
          };
          paths = lib.concatMap (name: selectedByName.${name}) resolved.order;
        in
        {
          inherit (resolved)
            order
            capabilityEdges
            capabilityRequirements
            ;
          inherit paths disabled disabledReasons;
        };

      globalHomeSelection = selectLocalModules {
        side = "home";
        roles = null;
        overrideMap = { };
        target = "global home";
      };

      hostPlans = lib.mapAttrs (
        host: record:
        let
          metadata = hostMeta.normalizeHostMetadata record.meta;
          declaredProfiles = profileTools.checkHostProfiles {
            inherit host;
            declared = metadata.profiles;
            knownProfiles = discovered.profiles;
          };
          profileMembers =
            side: lib.unique (lib.concatMap (profile: discovered.profiles.${profile}.${side}) declaredProfiles);
          overrideMap = moduleTools.validateModuleOverrides metadata.modules;
          select =
            side:
            selectLocalModules {
              inherit side overrideMap;
              inherit (metadata) roles;
              profileEnabled = profileMembers side;
              target = "host '${host}'";
            };
        in
        {
          inherit record metadata overrideMap;
          profiles = declaredProfiles;
          nixos = select "nixos";
          home = select "home";
        }
      ) discovered.hostsByName;

      homeModulesFor =
        {
          user,
          host ? null,
          selection ? if host == null then globalHomeSelection else hostPlans.${host}.home,
        }:
        let
          homeRecord =
            discovered.homesByUser.${user} or {
              defaultPath = null;
              hostModules = { };
            };
          ownDefault = lib.optional (homeRecord.defaultPath != null) homeRecord.defaultPath;
          ownHost = lib.optional (
            host != null && builtins.hasAttr host homeRecord.hostModules
          ) homeRecord.hostModules.${host};
        in
        selection.paths ++ discovered.registryModules.home ++ ownDefault ++ ownHost;

      moduleReportForHost =
        hostRecord:
        let
          plan = builtins.getAttr hostRecord.name hostPlans;
          reportSide =
            side:
            let
              selected = plan.${side};
            in
            {
              enabled = selected.order;
              inherit (selected)
                disabled
                disabledReasons
                capabilityEdges
                capabilityRequirements
                ;
            };
        in
        lib.genAttrs [ "nixos" "home" ] reportSide;

      mkSystem =
        {
          host,
          system ? null,
          modules ? [ ],
          extraModules ? [ ],
          extraNixosModules ? [ ],
          extraHomeModules ? [ ],
          extraSpecialArgs ? { },
          extraHomeSpecialArgs ? extraSpecialArgs,
          nixpkgsConfig ? { },
          extraOverlays ? [ ],
          embedHomeManager ? true,
          homeManagerUseGlobalPkgs ? true,
          _pkgs ? null,
        }:
        let
          plan = hostPlans.${host};
          hostRecord = plan.record;
          sys = if system == null then hostRecord.system else system;
          pkgs =
            if _pkgs == null then
              pkgsFor {
                system = sys;
                inherit nixpkgsConfig extraOverlays;
              }
            else
              _pkgs;
          specialArgs = specialArgsFor extraSpecialArgs;
          homeSpecialArgs = specialArgsFor extraHomeSpecialArgs;
          hostUsers = usersForHost host;
          hostUserRecords = map (name: discovered.usersByName.${name}) hostUsers;
          hostHomeUsers = lib.filter (name: builtins.hasAttr name discovered.homesByUser) hostUsers;

          inherit (plan) metadata;
          embedForHost = hostMeta.hostPolicyFromMetadata {
            inherit metadata host;
            key = "embedHomeManager";
            fallback = hostMeta.resolveHostPolicy {
              name = "embedHomeManager";
              value = embedHomeManager;
              inherit host;
              default = true;
            };
          };
          useGlobalPkgs = hostMeta.hostPolicyFromMetadata {
            inherit metadata host;
            key = "homeManagerUseGlobalPkgs";
            fallback = hostMeta.resolveHostPolicy {
              name = "homeManagerUseGlobalPkgs";
              inherit host;
              value = homeManagerUseGlobalPkgs;
              default = true;
            };
          };

          hostModules = plan.nixos.paths ++ discovered.registryModules.nixos ++ hostRecord.modulePaths;

          userDefaultsModule = userTools.mkUsersModule {
            users = map (u: {
              inherit (u) name;
              inherit (u) meta;
            }) hostUserRecords;
            sopsFile = sops'.hostFile host;
          };
          userDefaultModules = lib.filter (p: p != null) (map (u: u.defaultPath) hostUserRecords);

          embedModule =
            { config, lib, ... }:
            let
              bfe = config.snowveil.homeManager.backupFileExtension;
            in
            {
              imports = [
                (
                  if hm == null then
                    throw "host '${host}' has associated homes (${lib.concatStringsSep ", " hostHomeUsers}) but no home-manager input is available"
                  else
                    hm.nixosModules.home-manager
                )
              ];
              home-manager = {
                inherit useGlobalPkgs;
                useUserPackages = true;
                extraSpecialArgs = homeSpecialArgs;
                users = lib.genAttrs hostHomeUsers (
                  u:
                  {
                    imports =
                      homeModulesFor {
                        user = u;
                        inherit host;
                        selection = plan.home;
                      }
                      ++ extraModules
                      ++ extraHomeModules;
                  }
                  // lib.optionalAttrs (!useGlobalPkgs) {
                    nixpkgs = {
                      config = nixpkgsConfig;
                      overlays = overlayList ++ extraOverlays;
                    };
                  }
                );
              }
              // lib.optionalAttrs (bfe != null) { backupFileExtension = bfe; };
            };

          setSnowveilModule = _: { config.snowveil.users = hostUsers; };

          finalModules = [
            optionsSnowveil
            setSnowveilModule
            (_: { nixpkgs = { inherit pkgs; }; })
          ]
          ++ lib.optionals (hostUserRecords != [ ]) [ userDefaultsModule ]
          ++ userDefaultModules
          ++ lib.optionals (embedForHost && hostHomeUsers != [ ]) [ embedModule ]
          ++ hostModules
          ++ modules
          ++ extraModules
          ++ extraNixosModules;
        in
        nixosSystem {
          system = sys;
          inherit specialArgs;
          modules = finalModules;
        };

      mkHome =
        {
          user,
          host ? null,
          system ? null,
          modules ? [ ],
          extraModules ? [ ],
          extraHomeModules ? [ ],
          extraSpecialArgs ? { },
          nixpkgsConfig ? { },
          extraOverlays ? [ ],
          _pkgs ? null,
        }:
        let
          hmLib =
            if hm == null then
              throw "mkHome requires a home-manager input; add one to flake inputs"
            else
              hm.lib;
          sys =
            if host != null then
              (hostMeta.resolveHost host).system
            else if system != null then
              system
            else
              lib.head defaultSystems;
          pkgs =
            if _pkgs == null then
              pkgsFor {
                system = sys;
                inherit nixpkgsConfig extraOverlays;
              }
            else
              _pkgs;
          selection = if host == null then globalHomeSelection else hostPlans.${host}.home;
        in
        hmLib.homeManagerConfiguration {
          inherit pkgs;
          extraSpecialArgs = specialArgsFor extraSpecialArgs;
          modules = [
            optionsSnowveilHome
          ]
          ++ homeModulesFor {
            inherit user host selection;
          }
          ++ modules
          ++ extraModules
          ++ extraHomeModules;
        };

      mkFlake =
        # 扁平参数（extraOutputs / extraSpecialArgs / extraModules /
        # extraNixosModules / extraHomeModules / nixpkgsConfig / extraOverlays /
        # embedHomeManager / homeManagerUseGlobalPkgs / disabledOutputs /
        # expectedOutputs）仍受支持以保证向后兼容，通过 args_raw 读取。
        # 嵌套命名空间（nixpkgs / nixos / home / outputs）优先。
        args_raw@{
          systems ? defaultSystems,
          # nixpkgs = { config?; overlays?; }
          nixpkgs ? { },
          # nixos = { modules?; specialArgs?; }
          nixos ? { },
          # home = { modules?; specialArgs?; embed?; useGlobalPkgs?; }
          home ? { },
          # outputs = { extra?; disabled?; expected?; }
          outputs ? { },
          ...
        }:
        let
          # 解析嵌套命名空间，与扁平参数合并（嵌套命名空间优先）。
          # 扁平参数通过 args_raw 读取，避免 let 递归绑定遮蔽同名参数。
          flatOr = name: default: if builtins.hasAttr name args_raw then args_raw.${name} else default;

          nixpkgsConfig =
            if builtins.hasAttr "config" nixpkgs then nixpkgs.config else flatOr "nixpkgsConfig" { };
          extraOverlays =
            if builtins.hasAttr "overlays" nixpkgs then nixpkgs.overlays else flatOr "extraOverlays" [ ];
          legacySpecialArgs = flatOr "extraSpecialArgs" { };
          extraSpecialArgs =
            if builtins.hasAttr "specialArgs" nixos then nixos.specialArgs else legacySpecialArgs;
          extraHomeSpecialArgs =
            if builtins.hasAttr "specialArgs" home then home.specialArgs else legacySpecialArgs;
          # extraModules 同时注入 NixOS 与 HM 两侧；分组参数按侧注入。
          extraModules = flatOr "extraModules" [ ];
          extraNixosModules =
            if builtins.hasAttr "modules" nixos then nixos.modules else flatOr "extraNixosModules" [ ];
          extraHomeModules =
            if builtins.hasAttr "modules" home then home.modules else flatOr "extraHomeModules" [ ];
          embedHomeManager =
            if builtins.hasAttr "embed" home then home.embed else flatOr "embedHomeManager" true;
          homeManagerUseGlobalPkgs =
            if builtins.hasAttr "useGlobalPkgs" home then
              home.useGlobalPkgs
            else
              flatOr "homeManagerUseGlobalPkgs" true;
          extraOutputs =
            if builtins.hasAttr "extra" outputs then outputs.extra else flatOr "extraOutputs" { };
          disabledOutputs =
            if builtins.hasAttr "disabled" outputs then outputs.disabled else flatOr "disabledOutputs" [ ];
          expectedOutputs =
            if builtins.hasAttr "expected" outputs then outputs.expected else flatOr "expectedOutputs" { };
          homesStandalone =
            if builtins.hasAttr "homes" outputs && builtins.hasAttr "standalone" outputs.homes then
              outputs.homes.standalone
            else
              true;
          evalOutputs = outputs.eval or { };
          diagnosticsOutputs = outputs.diagnostics or { };
          packageSystems = lib.unique (systems ++ map (host: host.system) discovered.hosts);
          pkgsBySystem = lib.genAttrs packageSystems (
            system:
            pkgsFor {
              inherit system nixpkgsConfig extraOverlays;
            }
          );

          nixosConfigurations = lib.listToAttrs (
            map (
              h:
              lib.nameValuePair h.name (mkSystem {
                host = h.name;
                inherit (h) system;
                inherit
                  extraSpecialArgs
                  extraHomeSpecialArgs
                  extraModules
                  extraNixosModules
                  extraHomeModules
                  nixpkgsConfig
                  extraOverlays
                  embedHomeManager
                  homeManagerUseGlobalPkgs
                  ;
                _pkgs = pkgsBySystem.${h.system};
              })
            ) discovered.hosts
          );

          disabledSet =
            if builtins.isList disabledOutputs then
              lib.genAttrs disabledOutputs (_: true)
            else if builtins.isAttrs disabledOutputs then
              lib.mapAttrs (_: names: lib.genAttrs names (_: true)) disabledOutputs
            else
              throw "disabledOutputs must be a list of strings or an attrset mapping output names to lists of names";

          disabledByName =
            kind: name:
            if builtins.isList disabledOutputs then
              builtins.hasAttr "${kind}.${name}" disabledSet
              || (kind == "formatter" && name == "default" && builtins.hasAttr "formatter" disabledSet)
              || (kind == "deploy" && name == "default" && builtins.hasAttr "deploy" disabledSet)
            else
              builtins.hasAttr name (disabledSet.${kind} or { });

          disabledForSystem =
            kind: name: system:
            disabledByName kind name
            || (
              if builtins.isList disabledOutputs then
                builtins.hasAttr "${kind}.${system}.${name}" disabledSet
                || (kind == "formatter" && name == "default" && builtins.hasAttr "formatter.${system}" disabledSet)
              else
                builtins.hasAttr "${system}.${name}" (disabledSet.${kind} or { })
            );

          metadataEnabled =
            {
              kind,
              name,
              meta,
              system,
            }:
            let
              enabled = meta.enable or true;
              supportedSystems = meta.systems or null;
            in
            if !builtins.isBool enabled then
              throw "error: invalid meta value

  ${kind}.${name} meta.enable must be a boolean
  got: ${builtins.typeOf enabled}"
            else if
              supportedSystems != null
              && !(builtins.isList supportedSystems && lib.all builtins.isString supportedSystems)
            then
              throw "error: invalid meta value

  ${kind}.${name} meta.systems must be a list of strings
  got: ${builtins.typeOf supportedSystems}"
            else
              enabled
              && (supportedSystems == null || builtins.elem system supportedSystems)
              && !disabledForSystem kind name system;

          uniqueDefinitions =
            kind: system: definitions:
            let
              grouped = lib.groupBy (definition: definition.name) definitions;
              duplicates = builtins.attrNames (lib.filterAttrs (_: values: builtins.length values > 1) grouped);
            in
            if duplicates == [ ] then
              definitions
            else
              throw "error: duplicate names detected

  ${kind}.${system} contains duplicate definitions:
  ${lib.concatStringsSep ", " duplicates}";

          knownSystems = lib.unique (systems ++ lib.systems.flakeExposed);
          knownSystemsSet = lib.genAttrs knownSystems (_: true);
          packageDefs = map (
            package:
            let
              parts = lib.splitString "." package.name;
              suffix = lib.last parts;
              hasExplicitMetadata = package.meta ? systems;
              legacySystem =
                if
                  package.explicitSystem == null && !hasExplicitMetadata && builtins.hasAttr suffix knownSystemsSet
                then
                  suffix
                else
                  null;
              name = if legacySystem == null then package.name else lib.concatStringsSep "." (lib.init parts);
              supportedSystems =
                if package.explicitSystem != null then
                  [ package.explicitSystem ]
                else if hasExplicitMetadata then
                  package.meta.systems
                else if legacySystem != null then
                  [ legacySystem ]
                else
                  null;
            in
            package
            // {
              inherit name supportedSystems;
              meta = package.meta // lib.optionalAttrs (supportedSystems != null) { systems = supportedSystems; };
            }
          ) discovered.packages;

          packages = forAllSystems systems (
            sys:
            let
              pkgs = pkgsBySystem.${sys};
              definitions = uniqueDefinitions "packages" sys (
                lib.filter (
                  package:
                  (package.explicitSystem == null || package.explicitSystem == sys)
                  && metadataEnabled {
                    kind = "packages";
                    inherit (package) name meta;
                    system = sys;
                  }
                ) packageDefs
              );
            in
            lib.listToAttrs (map (p: lib.nameValuePair p.name (callPackage pkgs p.path)) definitions)
          );

          namedSystemOutputs =
            kind: definitions:
            forAllSystems systems (
              sys:
              let
                pkgs = pkgsBySystem.${sys};
                enabled = lib.filter (
                  d:
                  metadataEnabled {
                    inherit kind;
                    inherit (d) name meta;
                    system = sys;
                  }
                ) definitions;
              in
              lib.listToAttrs (map (d: lib.nameValuePair d.name (callPackage pkgs d.path)) enabled)
            );

          devShells = namedSystemOutputs "devShells" discovered.shells;
          discoveredChecks = namedSystemOutputs "checks" discovered.checks;
          apps = namedSystemOutputs "apps" discovered.apps;
          appsEnabled = lib.any (sys: apps.${sys} != { }) systems;

          formatter = lib.listToAttrs (
            lib.concatMap (
              sys:
              if
                metadataEnabled {
                  kind = "formatter";
                  name = "default";
                  inherit (discovered.formatter) meta;
                  system = sys;
                }
              then
                let
                  pkgs = pkgsBySystem.${sys};
                in
                [ (lib.nameValuePair sys (callPackage pkgs discovered.formatter.path)) ]
              else
                [ ]
            ) systems
          );

          deployEnabled =
            if discovered.deploy == null then
              false
            else if !builtins.isBool (discovered.deploy.meta.enable or true) then
              throw "error: invalid meta value

  deploy meta.enable must be a boolean
  got: ${builtins.typeOf discovered.deploy.meta.enable}"
            else
              (discovered.deploy.meta.enable or true) && !disabledByName "deploy" "default";
          deploy = importFile discovered.deploy.path;

          userLib = lib.listToAttrs (
            map (
              f: lib.nameValuePair (lib.removeSuffix ".nix" f.name) (importFile (projectRoot + "/lib/" + f.name))
            ) discovered.libFiles
          );

          homeConfigurations =
            let
              global = lib.listToAttrs (
                map (
                  h:
                  lib.nameValuePair h.user (mkHome {
                    inherit (h) user;
                    system = lib.head systems;
                    extraSpecialArgs = extraHomeSpecialArgs;
                    inherit
                      extraModules
                      extraHomeModules
                      nixpkgsConfig
                      extraOverlays
                      ;
                    _pkgs = pkgsBySystem.${lib.head systems};
                  })
                ) (lib.filter (homeRecord: homeRecord.defaultPath != null) discovered.homes)
              );
              perHost = lib.listToAttrs (
                lib.concatMap (
                  h:
                  map (
                    host:
                    lib.nameValuePair "${h.user}@${host}" (mkHome {
                      inherit (h) user;
                      extraSpecialArgs = extraHomeSpecialArgs;
                      inherit
                        host
                        extraModules
                        extraHomeModules
                        nixpkgsConfig
                        extraOverlays
                        ;
                      _pkgs = pkgsBySystem.${discovered.hostsByName.${host}.system};
                    })
                  ) (lib.filter (host: builtins.hasAttr host discovered.hostsByName) h.hosts)
                ) discovered.homes
              );
            in
            if homesStandalone then global // perHost else perHost;

          images = lib.mapAttrs (
            host: cfg:
            let
              hostRec = hostMeta.resolveHost host;
              fmts = hostRec.meta.images.formats or [ ];
              avail = cfg.config.system.build.images;
            in
            lib.genAttrs fmts (
              f:
              if builtins.hasAttr f avail then
                avail.${f}
              else
                throw "error: image format not supported

  host '${host}' requested image format '${f}'
  but this format is not available in the current nixpkgs
  hint: check available formats with 'nixos-rebuild help-images'"
            )
          ) nixosConfigurations;

          systemsSet = lib.genAttrs systems (_: true);
          checks = forAllSystems systems (
            sys:
            let
              pkgs = pkgsBySystem.${sys};
              discoveredHosts = map (host: host.name) discovered.hosts;
              discoveredHomes = builtins.attrNames homeConfigurations;
              discoveredPkgs = builtins.attrNames packages.${sys};
              discoveredApps = if appsEnabled then builtins.attrNames apps.${sys} else [ ];
              discoveredShells = builtins.attrNames devShells.${sys};
              discoveredUserChecks = builtins.attrNames discoveredChecks.${sys};
              discoveredOverlays = builtins.attrNames overlays;
              discoveredNixosModules = builtins.attrNames discovered.localGroupedModules.nixos;
              discoveredHomeModules = builtins.attrNames discovered.localGroupedModules.home;
              discoveredFormatter = lib.optional (builtins.hasAttr sys formatter) sys;
              discoveredDeploy =
                lib.optional deployEnabled "present"
                ++ lib.optionals (
                  deployEnabled && builtins.isAttrs deploy && builtins.isAttrs (deploy.nodes or null)
                ) (map (name: "nodes.${name}") (builtins.attrNames deploy.nodes));
              discoveredImages = lib.concatMap (
                hostRecord: map (format: "${hostRecord.name}.${format}") (hostRecord.meta.images.formats or [ ])
              ) discovered.hosts;

              checkedExpectedOutputs =
                if builtins.isAttrs expectedOutputs then
                  expectedOutputs
                else
                  throw "outputs.expected must be an attribute set";
              expectedMode = checkedExpectedOutputs.mode or "subset";
              supportedExpectedFields = [
                "hosts"
                "homes"
                "packages"
                "apps"
                "checks"
                "devShells"
                "overlays"
                "nixosModules"
                "homeModules"
                "formatter"
                "deploy"
                "images"
              ];
              supportedExpectedFieldsSet = lib.genAttrs supportedExpectedFields (_: true);
              expectedFields = builtins.removeAttrs checkedExpectedOutputs [ "mode" ];
              unknownExpectedFields = lib.filter (name: !builtins.hasAttr name supportedExpectedFieldsSet) (
                builtins.attrNames expectedFields
              );
              checkedExpectedFields =
                if
                  !builtins.hasAttr expectedMode {
                    subset = true;
                    exact = true;
                  }
                then
                  throw "outputs.expected.mode must be \"subset\" or \"exact\""
                else if unknownExpectedFields != [ ] then
                  throw "outputs.expected contains unsupported fields: ${lib.concatStringsSep ", " unknownExpectedFields}"
                else
                  expectedFields;

              stringList =
                label: value:
                if builtins.isList value && lib.all builtins.isString value then
                  lib.unique value
                else
                  throw "outputs.expected.${label} must be a list of strings";
              perSystemExpected =
                kind: value:
                if builtins.isList value then
                  stringList kind value
                else if builtins.isAttrs value then
                  let
                    unknownSystems = lib.filter (system: !builtins.hasAttr system systemsSet) (
                      builtins.attrNames value
                    );
                    validated = lib.mapAttrs (system: items: stringList "${kind}.${system}" items) value;
                  in
                  if unknownSystems != [ ] then
                    throw "outputs.expected.${kind} contains unconfigured systems: ${lib.concatStringsSep ", " unknownSystems}"
                  else
                    builtins.deepSeq validated (validated.${sys} or [ ])
                else
                  throw "outputs.expected.${kind} must be a list of strings or an attrset mapping systems to lists of strings";
              formatterExpected =
                value:
                let
                  configured = stringList "formatter" value;
                  unknownSystems = lib.filter (system: !builtins.hasAttr system systemsSet) configured;
                in
                if unknownSystems != [ ] then
                  throw "outputs.expected.formatter contains unconfigured systems: ${lib.concatStringsSep ", " unknownSystems}"
                else
                  lib.filter (system: system == sys) configured;
              deployExpected =
                value:
                if !builtins.isAttrs value then
                  throw "outputs.expected.deploy must be an attribute set"
                else
                  let
                    present = value.present or false;
                    nodes = stringList "deploy.nodes" (value.nodes or [ ]);
                  in
                  if !builtins.isBool present then
                    throw "outputs.expected.deploy.present must be a boolean"
                  else
                    lib.optional present "present" ++ map (name: "nodes.${name}") nodes;
              imagesExpected =
                value:
                if !builtins.isAttrs value then
                  throw "outputs.expected.images must be an attrset mapping hosts to lists of image formats"
                else
                  lib.concatLists (
                    lib.mapAttrsToList (
                      host: formats: map (format: "${host}.${format}") (stringList "images.${host}" formats)
                    ) value
                  );
              expectedFor =
                kind:
                let
                  value =
                    checkedExpectedFields.${kind} or (
                      if
                        builtins.hasAttr kind {
                          deploy = true;
                          images = true;
                        }
                      then
                        { }
                      else
                        [ ]
                    );
                in
                if
                  builtins.hasAttr kind {
                    packages = true;
                    apps = true;
                    checks = true;
                    devShells = true;
                  }
                then
                  perSystemExpected kind value
                else if kind == "formatter" then
                  formatterExpected value
                else if kind == "deploy" then
                  deployExpected value
                else if kind == "images" then
                  imagesExpected value
                else
                  stringList kind value;
              actualFor = {
                hosts = discoveredHosts;
                homes = discoveredHomes;
                packages = discoveredPkgs;
                apps = discoveredApps;
                checks = discoveredUserChecks;
                devShells = discoveredShells;
                overlays = discoveredOverlays;
                nixosModules = discoveredNixosModules;
                homeModules = discoveredHomeModules;
                formatter = discoveredFormatter;
                deploy = discoveredDeploy;
                images = discoveredImages;
              };
              kindsToCheck =
                if expectedMode == "exact" then
                  supportedExpectedFields
                else
                  builtins.attrNames checkedExpectedFields;
              checkExpected =
                kind:
                let
                  expected = lib.unique (expectedFor kind);
                  actual = lib.unique actualFor.${kind};
                  actualSet = lib.genAttrs actual (_: true);
                  expectedSet = lib.genAttrs expected (_: true);
                  missing = sortNames (lib.filter (item: !builtins.hasAttr item actualSet) expected);
                  unexpected =
                    if expectedMode == "exact" then
                      sortNames (lib.filter (item: !builtins.hasAttr item expectedSet) actual)
                    else
                      [ ];
                  script = pkgs.writeShellScript "check-discovery-${kind}-${sys}" ''
                    set -euo pipefail
                    missing=${lib.escapeShellArg (builtins.toJSON missing)}
                    unexpected=${lib.escapeShellArg (builtins.toJSON unexpected)}
                    if [ "$missing" != "[]" ]; then
                      echo "snowveil-discovery: outputs.expected.${kind} is missing the following entries:" >&2
                      echo "$missing" | ${pkgs.jq}/bin/jq -r '.[]' | sed 's/^/  - /' >&2
                    fi
                    if [ "$unexpected" != "[]" ]; then
                      echo "snowveil-discovery: outputs.expected.${kind} contains the following unexpected entries:" >&2
                      echo "$unexpected" | ${pkgs.jq}/bin/jq -r '.[]' | sed 's/^/  - /' >&2
                    fi
                    if [ "$missing" != "[]" ] || [ "$unexpected" != "[]" ]; then
                      exit 1
                    fi
                    touch "$out"
                  '';
                in
                pkgs.runCommand "snowveil-discovery-check-${kind}-${sys}" { } "bash ${script}";
              expectedChecks = lib.listToAttrs (
                map (
                  kind: lib.nameValuePair "snowveil-discovery-expected-${kind}" (checkExpected kind)
                ) kindsToCheck
              );

              checkedEvalOutputs =
                if builtins.isAttrs evalOutputs then evalOutputs else throw "outputs.eval must be an attribute set";
              evalKeys = builtins.attrNames checkedEvalOutputs;
              invalidEvalKeys = lib.filter (
                name:
                !builtins.hasAttr name {
                  hosts = true;
                  homes = true;
                }
              ) evalKeys;
              evalHosts = checkedEvalOutputs.hosts or false;
              evalHomes = checkedEvalOutputs.homes or false;
              evalSelection =
                kind: available: value:
                if builtins.isBool value then
                  if value then available else [ ]
                else if builtins.isList value && lib.all builtins.isString value then
                  let
                    selected = lib.unique value;
                    availableSet = lib.genAttrs available (_: true);
                    unknown = lib.filter (name: !builtins.hasAttr name availableSet) selected;
                  in
                  if unknown == [ ] then
                    selected
                  else
                    throw "outputs.eval.${kind} references undiscovered targets: ${lib.concatStringsSep ", " unknown}"
                else
                  throw "outputs.eval.${kind} must be a boolean or a list of strings";
              selectedEvalHosts = evalSelection "hosts" discoveredHosts evalHosts;
              selectedEvalHomes = evalSelection "homes" discoveredHomes evalHomes;
              checkedEval =
                if invalidEvalKeys != [ ] then
                  throw "outputs.eval contains unsupported fields: ${lib.concatStringsSep ", " invalidEvalKeys}"
                else
                  builtins.deepSeq selectedEvalHosts (builtins.deepSeq selectedEvalHomes true);
              selectedEvalHostSet = lib.genAttrs selectedEvalHosts (_: true);
              hostEvalRecords =
                map
                  (hostRecord: {
                    inherit (hostRecord) name;
                    drvPath =
                      builtins.unsafeDiscardStringContext
                        nixosConfigurations.${hostRecord.name}.config.system.build.toplevel.drvPath;
                  })
                  (
                    lib.filter (
                      hostRecord: hostRecord.system == sys && builtins.hasAttr hostRecord.name selectedEvalHostSet
                    ) discovered.hosts
                  );
              systemForHome =
                name:
                if lib.hasInfix "@" name then
                  discovered.hostsByName.${lib.last (lib.splitString "@" name)}.system
                else
                  lib.head systems;
              homeEvalRecords = map (name: {
                inherit name;
                drvPath = builtins.unsafeDiscardStringContext homeConfigurations.${name}.activationPackage.drvPath;
              }) (lib.filter (name: systemForHome name == sys) selectedEvalHomes);
              evalChecks =
                assert checkedEval;
                lib.optionalAttrs (evalHosts == true || hostEvalRecords != [ ]) {
                  snowveil-eval-hosts = pkgs.writeText "snowveil-eval-hosts-${sys}.json" (
                    builtins.toJSON hostEvalRecords
                  );
                }
                // lib.optionalAttrs (evalHomes == true || homeEvalRecords != [ ]) {
                  snowveil-eval-homes = pkgs.writeText "snowveil-eval-homes-${sys}.json" (
                    builtins.toJSON homeEvalRecords
                  );
                };

              checkedDiagnosticsOutputs =
                if builtins.isAttrs diagnosticsOutputs then
                  diagnosticsOutputs
                else
                  throw "outputs.diagnostics must be an attribute set";
              diagnosticKeys = builtins.attrNames checkedDiagnosticsOutputs;
              supportedDiagnosticKeys = [
                "discovery"
                "moduleGraph"
                "perHostModuleGraph"
              ];
              supportedDiagnosticKeysSet = {
                discovery = true;
                moduleGraph = true;
                perHostModuleGraph = true;
              };
              invalidDiagnosticKeys = lib.filter (
                name: !builtins.hasAttr name supportedDiagnosticKeysSet
              ) diagnosticKeys;
              diagnostics = {
                discovery = checkedDiagnosticsOutputs.discovery or true;
                moduleGraph = checkedDiagnosticsOutputs.moduleGraph or true;
                perHostModuleGraph = checkedDiagnosticsOutputs.perHostModuleGraph or false;
              };
              invalidDiagnosticValues = lib.filter (
                name: !builtins.isBool diagnostics.${name}
              ) supportedDiagnosticKeys;
              checkedDiagnostics =
                if invalidDiagnosticKeys != [ ] then
                  throw "outputs.diagnostics contains unsupported fields: ${lib.concatStringsSep ", " invalidDiagnosticKeys}"
                else if invalidDiagnosticValues != [ ] then
                  throw "outputs.diagnostics fields must be booleans: ${lib.concatStringsSep ", " invalidDiagnosticValues}"
                else
                  true;

              graphReport = lib.mapAttrs (_: graph: {
                inherit (graph)
                  order
                  edges
                  groups
                  capabilities
                  ;
                nodes = builtins.attrNames graph.nodes;
                details = lib.mapAttrs (_: node: {
                  inherit (node)
                    requires
                    requiresGroups
                    provides
                    requiresCapabilities
                    after
                    before
                    wants
                    conflicts
                    ;
                }) graph.nodes;
              }) discovered.moduleGraph;
              perHostReport =
                if diagnostics.perHostModuleGraph then
                  builtins.listToAttrs (
                    map (
                      hostRecord: lib.nameValuePair hostRecord.name (moduleReportForHost hostRecord)
                    ) discovered.hosts
                  )
                else
                  { };
              report = {
                schemaVersion = 1;
                discoverySpecVersion = "1.3";
                frameworkVersion = version.string;
                system = sys;
                hosts = discoveredHosts;
                hostFiles = builtins.listToAttrs (
                  map (
                    hostRecord: lib.nameValuePair hostRecord.name (map baseNameOf hostRecord.modulePaths)
                  ) discovered.hosts
                );
                inherit (discovered) profiles;
                hostProfiles = builtins.listToAttrs (
                  map (
                    hostRecord: lib.nameValuePair hostRecord.name hostPlans.${hostRecord.name}.profiles
                  ) discovered.hosts
                );
                homes = discoveredHomes;
                packages = discoveredPkgs;
                apps = discoveredApps;
                checks = discoveredUserChecks;
                devShells = discoveredShells;
                overlays = discoveredOverlays;
                nixosModules = discoveredNixosModules;
                homeModules = discoveredHomeModules;
                formatter = discoveredFormatter;
                deploy = discoveredDeploy;
                images = discoveredImages;
                moduleGraph = graphReport;
                perHost = perHostReport;
              };

              dotEscape = value: builtins.replaceStrings [ "\\" "\"" ] [ "\\\\" "\\\"" ] value;
              dotFor =
                name: nodes: edges:
                let
                  selected = sortNames nodes;
                  selectedSet = lib.genAttrs selected (_: true);
                  selectedEdges = lib.filter (
                    edge: builtins.hasAttr edge.from selectedSet && builtins.hasAttr edge.to selectedSet
                  ) edges;
                  nodeLines = map (node: "  \"${dotEscape node}\";") selected;
                  edgeLines = map (
                    edge: "  \"${dotEscape edge.to}\" -> \"${dotEscape edge.from}\" [label=\"${dotEscape edge.kind}\"];"
                  ) selectedEdges;
                in
                lib.concatStringsSep "\n" (
                  [
                    "digraph \"${dotEscape name}\" {"
                    "  rankdir=LR;"
                  ]
                  ++ nodeLines
                  ++ edgeLines
                  ++ [ "}" ]
                )
                + "\n";
              globalDotFiles =
                lib.concatMap
                  (side: [
                    {
                      path = "${side}.dot";
                      text = dotFor side (builtins.attrNames
                        discovered.moduleGraph.${side}.nodes
                      ) discovered.moduleGraph.${side}.edges;
                    }
                  ])
                  [
                    "nixos"
                    "home"
                  ];
              hostDotFiles = lib.concatMap (
                host:
                lib.concatMap
                  (
                    side:
                    let
                      hostSide = perHostReport.${host}.${side};
                    in
                    [
                      {
                        path = "hosts/${host}/${side}.dot";
                        text = dotFor "${host}-${side}" hostSide.enabled (
                          discovered.moduleGraph.${side}.edges ++ hostSide.capabilityEdges
                        );
                      }
                    ]
                  )
                  [
                    "nixos"
                    "home"
                  ]
              ) (builtins.attrNames perHostReport);
              dotFiles = globalDotFiles ++ hostDotFiles;
              dotCheck = pkgs.runCommand "snowveil-module-graph-dot-${sys}" { } ''
                mkdir -p "$out"
                ${lib.concatMapStringsSep "\n" (
                  file:
                  let
                    sourceFile = pkgs.writeText (baseNameOf file.path) file.text;
                  in
                  ''
                    mkdir -p "$out/${builtins.dirOf file.path}"
                    cp ${sourceFile} "$out/${file.path}"
                  ''
                ) dotFiles}
              '';
              reservedCollision = lib.findFirst (name: lib.hasPrefix "snowveil-" name) null discoveredUserChecks;
            in
            if reservedCollision != null then
              throw ''
                reserved output name

                'checks.${reservedCollision}' uses the framework-reserved snowveil- prefix
                hint: use a different name for your check
              ''
            else
              assert checkedDiagnostics;
              discoveredChecks.${sys}
              // expectedChecks
              // evalChecks
              // lib.optionalAttrs diagnostics.discovery {
                snowveil-discovery = pkgs.writeText "snowveil-discovery-${sys}.json" (builtins.toJSON report);
              }
              // lib.optionalAttrs diagnostics.moduleGraph {
                snowveil-module-graph-dot = dotCheck;
              }
          );

          moduleOutput = paths: { imports = paths; };

          # User flake output schema declaration
          userFlakeSchema = {
            description = "Flake output schema generated by Snowveil framework";
            outputs = {
              nixosConfigurations = "NixOS host configurations";
              homeConfigurations = "Home Manager user configurations";
              packages = "per-system buildable packages";
              apps = "per-system application wrappers";
              devShells = "development environment shells";
              overlays = "nixpkgs overlays";
              checks = "tests and verification checks";
              nixosModules = "reusable NixOS modules";
              homeModules = "reusable Home Manager modules";
              images = "system image outputs (NixOS ISO, VM images, etc.)";
              deploy = "deploy configuration";
              formatter = "code formatting tool";
              lib = "project-specific library functions";
            };
          };

          generated = {
            inherit
              nixosConfigurations
              homeConfigurations
              packages
              devShells
              checks
              overlays
              images
              ;
            lib = userLib;
            nixosModules = lib.mapAttrs (_: moduleOutput) discovered.localGroupedModules.nixos;
            homeModules = lib.mapAttrs (_: moduleOutput) discovered.localGroupedModules.home;
            flakeOutputsSchema = userFlakeSchema;
          }
          // lib.optionalAttrs appsEnabled { inherit apps; }
          // lib.optionalAttrs (discovered.formatter != null && formatter != { }) { inherit formatter; }
          // lib.optionalAttrs deployEnabled { inherit deploy; };
        in
        lib.recursiveUpdate generated extraOutputs;
    in
    {
      inherit
        mkFlake
        mkSystem
        mkHome
        forAllSystems
        version
        ;
      inherit (fs) importModules flattenTree groupModules;
      inherit
        patches
        source
        projectSource
        ;
      sops = sops';
    };

  mkLib = { inputs }: bind { inherit inputs; };

  mkFlake =
    args@{ inputs, ... }:
    let
      inputsPos = builtins.unsafeGetAttrPos "inputs" args;
      root =
        args.root or (if inputsPos != null then builtins.dirOf inputsPos.file else inputs.self.outPath);
    in
    (bind {
      inherit inputs root;
      moduleRegistries = args.moduleRegistries or [ ];
      moduleGroups = args.moduleGroups or { };
      profiles = args.profiles or { };
    }).mkFlake
      (
        builtins.removeAttrs args [
          "inputs"
          "moduleRegistries"
          "moduleGroups"
          "profiles"
          "root"
        ]
      );
in
{
  inherit
    mkLib
    mkFlake
    forAllSystems
    renderOptions
    version
    ;
  inherit (fs) importModules flattenTree groupModules;
  inherit patches;
  source = sourceTools;
}
