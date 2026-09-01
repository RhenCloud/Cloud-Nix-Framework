{ lib }:

# Cloud Nix Framework - 库入口
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

  renderOptions =
    opts:
    let
      isOpt =
        o:
        builtins.isAttrs o
        && (
          (o._type or "") == "option"
          || (o ? type && builtins.isAttrs o.type && (o.type._type or "") == "option-type")
        );
      leaf = o: {
        type =
          let
            t = o.type or null;
          in
          if t == null then null else t.name or t.description or "unknown";
        description = o.description or null;
        default =
          let
            d = builtins.tryEval (o.default or null);
          in
          if d.success then (builtins.tryEval (builtins.toJSON d.value)).value else null;
      };
      go =
        o:
        if isOpt o then
          leaf o
        else if builtins.isAttrs o then
          lib.mapAttrs (k: go) o
        else
          o;
    in
    lib.mapAttrs (k: go) opts;

  optionsCloud =
    { lib, ... }:
    {
      options.cloud = {
        users = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [ ];
        };
        homeManager = {
          backupFileExtension = lib.mkOption {
            type = lib.types.nullOr lib.types.str;
            default = null;
            description = "嵌入式 home-manager 的 backupFileExtension；仅当该主机启用了 HM 嵌入时生效";
          };
          embed = lib.mkOption {
            type = lib.types.nullOr lib.types.bool;
            default = null;
            description = "仅读取用；实际嵌入策略由 hosts/<host>/meta.nix 的 home.embed 字段或 mkFlake 的 embedHomeManager 参数控制";
          };
        };
      };
    };

  optionsCloudHome =
    { lib, ... }:
    {
      options.cloud = {
        users = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [ ];
        };
      };
    };

  bind =
    {
      inputs,
      moduleRegistries ? [ ],
      moduleGroups ? { },
      root ? null,
    }:
    let
      self =
        inputs.self
          or (throw "error: missing required flake input

  Cloud Nix Framework requires inputs.self
  make sure 'self' is included in your flake inputs");
      nixpkgs =
        inputs.nixpkgs
          or (throw "error: missing required flake input

  Cloud Nix Framework requires inputs.nixpkgs
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
      cloudInject = {
        inherit
          patches
          version
          source
          projectSource
          ;
        sops = sops';
      };
      cloud = cloudInject;

      # overlays: 支持两种签名
      #   final: prev: { ... }                      标准 nixpkgs overlay
      #   extras: final: prev: ...                  带框架参数的扩展签名（extras = { inputs, self, cloud }）
      #   { inputs, self, cloud }: final: prev: ... 带框架参数的解构签名
      loadOverlay =
        path:
        let
          imported = import path;
          argNames = builtins.functionArgs imported;
          isStructuredArgs = argNames ? inputs || argNames ? self || argNames ? cloud;
        in
        if isStructuredArgs then
          imported { inherit inputs self cloud; }
        else
          let
            result = builtins.tryEval (imported {
              inherit inputs self cloud;
            });
          in
          if result.success && builtins.isFunction result.value then result.value else imported;

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
              cloud
              ;
          };
        in
        if builtins.isFunction imported then imported args else imported;

      callPackage =
        pkgs: path:
        let
          fn = import path;
          declared = builtins.functionArgs fn;
          extras = lib.intersectAttrs declared { inherit inputs self cloud; };
        in
        pkgs.callPackage fn extras;

      specialArgsFor =
        extraSpecialArgs:
        {
          inherit
            inputs
            self
            channels
            cloud
            ;
        }
        // extraSpecialArgs;

      usersForHost = host: discovered.usersByHost.${host} or [ ];

      selectLocalModules =
        {
          side,
          roles,
          overrideMap,
          target,
        }:
        let
          graph = discovered.moduleGraph.${side};
          moduleIndex = discovered.localGroupedModules.index;
          sideOnly = if side == "nixos" then "nixosOnly" else "homeOnly";
          rolesSet = if roles == null then null else lib.genAttrs roles (_: true);
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
            else if override == true then
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
                if (overrideMap.${name} or null) == false then "被主机模块覆盖显式禁用" else "未被角色过滤选中"
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
        target = "全局 home";
      };

      hostPlans = lib.mapAttrs (
        host: record:
        let
          metadata = hostMeta.normalizeHostMetadata record.meta;
          overrideMap = moduleTools.validateModuleOverrides metadata.modules;
          select =
            side:
            selectLocalModules {
              inherit side overrideMap;
              inherit (metadata) roles;
              target = "主机 '${host}'";
            };
        in
        {
          inherit record metadata overrideMap;
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
          hostModule = hostRecord.path;
          specialArgs = specialArgsFor extraSpecialArgs;
          homeSpecialArgs = specialArgsFor extraHomeSpecialArgs;
          users = usersForHost host;

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

          hostMod = import hostModule;
          hostModules = plan.nixos.paths ++ discovered.registryModules.nixos ++ [ hostMod ];

          embedModule =
            { config, lib, ... }:
            let
              bfe = config.cloud.homeManager.backupFileExtension;
            in
            {
              imports = [
                (
                  if hm == null then
                    throw "主机 '${host}' 关联了 home（${lib.concatStringsSep ", " users}），但缺少 home-manager input"
                  else
                    hm.nixosModules.home-manager
                )
              ];
              home-manager = {
                inherit useGlobalPkgs;
                useUserPackages = true;
                extraSpecialArgs = homeSpecialArgs;
                users = lib.genAttrs users (
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

          setCloudModule = _: { config.cloud.users = users; };

          finalModules = [
            optionsCloud
            setCloudModule
            (_: { nixpkgs = { inherit pkgs; }; })
          ]
          ++ lib.optionals (embedForHost && users != [ ]) [ embedModule ]
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
            if hm == null then throw "mkHome 需要 home-manager input，请在 flake inputs 中 follows" else hm.lib;
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
            optionsCloudHome
          ]
          ++ homeModulesFor {
            inherit user host selection;
          }
          ++ modules
          ++ extraModules
          ++ extraHomeModules;
        };

      mkFlake =
        args_raw@{
          systems ? defaultSystems,
          # --- 扁平参数（向后兼容，已弃用；请使用嵌套命名空间） ---
          extraOutputs ? { },
          extraSpecialArgs ? { },
          extraModules ? [ ],
          extraNixosModules ? [ ],
          extraHomeModules ? [ ],
          nixpkgsConfig ? { },
          extraOverlays ? [ ],
          embedHomeManager ? true,
          homeManagerUseGlobalPkgs ? true,
          disabledOutputs ? [ ],
          expectedOutputs ? { },
          # --- 嵌套命名空间（推荐） ---
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
          flatOr =
            name: default:
            if builtins.hasAttr name args_raw then
              builtins.trace "[CNF] mkFlake 参数 '${name}' 已弃用，请使用嵌套命名空间（见文档）" args_raw.${name}
            else
              default;

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
              throw "disabledOutputs 必须是字符串列表或 output 名到名称列表的属性集";

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
            global // perHost;

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
                if builtins.isAttrs expectedOutputs then expectedOutputs else throw "outputs.expected 必须是属性集";
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
                  throw "outputs.expected.mode 必须是 \"subset\" 或 \"exact\""
                else if unknownExpectedFields != [ ] then
                  throw "outputs.expected 包含不支持的字段：${lib.concatStringsSep ", " unknownExpectedFields}"
                else
                  expectedFields;

              stringList =
                label: value:
                if builtins.isList value && lib.all builtins.isString value then
                  lib.unique value
                else
                  throw "outputs.expected.${label} 必须是字符串列表";
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
                    throw "outputs.expected.${kind} 包含未配置的 system：${lib.concatStringsSep ", " unknownSystems}"
                  else
                    builtins.deepSeq validated (validated.${sys} or [ ])
                else
                  throw "outputs.expected.${kind} 必须是字符串列表或 system 到字符串列表的属性集";
              formatterExpected =
                value:
                let
                  configured = stringList "formatter" value;
                  unknownSystems = lib.filter (system: !builtins.hasAttr system systemsSet) configured;
                in
                if unknownSystems != [ ] then
                  throw "outputs.expected.formatter 包含未配置的 system：${lib.concatStringsSep ", " unknownSystems}"
                else
                  lib.filter (system: system == sys) configured;
              deployExpected =
                value:
                if !builtins.isAttrs value then
                  throw "outputs.expected.deploy 必须是属性集"
                else
                  let
                    present = value.present or false;
                    nodes = stringList "deploy.nodes" (value.nodes or [ ]);
                  in
                  if !builtins.isBool present then
                    throw "outputs.expected.deploy.present 必须是布尔值"
                  else
                    lib.optional present "present" ++ map (name: "nodes.${name}") nodes;
              imagesExpected =
                value:
                if !builtins.isAttrs value then
                  throw "outputs.expected.images 必须是 host 到镜像格式列表的属性集"
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
                      echo "cloud-discovery: outputs.expected.${kind} 缺少以下项目：" >&2
                      echo "$missing" | ${pkgs.jq}/bin/jq -r '.[]' | sed 's/^/  - /' >&2
                    fi
                    if [ "$unexpected" != "[]" ]; then
                      echo "cloud-discovery: outputs.expected.${kind} 包含以下意外项目：" >&2
                      echo "$unexpected" | ${pkgs.jq}/bin/jq -r '.[]' | sed 's/^/  - /' >&2
                    fi
                    if [ "$missing" != "[]" ] || [ "$unexpected" != "[]" ]; then
                      exit 1
                    fi
                    touch "$out"
                  '';
                in
                pkgs.runCommand "cloud-discovery-check-${kind}-${sys}" { } "bash ${script}";
              expectedChecks = lib.listToAttrs (
                map (kind: lib.nameValuePair "cloud-discovery-expected-${kind}" (checkExpected kind)) kindsToCheck
              );

              checkedEvalOutputs =
                if builtins.isAttrs evalOutputs then evalOutputs else throw "outputs.eval 必须是属性集";
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
                    throw "outputs.eval.${kind} 包含未发现的目标：${lib.concatStringsSep ", " unknown}"
                else
                  throw "outputs.eval.${kind} 必须是布尔值或字符串列表";
              selectedEvalHosts = evalSelection "hosts" discoveredHosts evalHosts;
              selectedEvalHomes = evalSelection "homes" discoveredHomes evalHomes;
              checkedEval =
                if invalidEvalKeys != [ ] then
                  throw "outputs.eval 包含不支持的字段：${lib.concatStringsSep ", " invalidEvalKeys}"
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
                  cloud-eval-hosts = pkgs.writeText "cloud-eval-hosts-${sys}.json" (builtins.toJSON hostEvalRecords);
                }
                // lib.optionalAttrs (evalHomes == true || homeEvalRecords != [ ]) {
                  cloud-eval-homes = pkgs.writeText "cloud-eval-homes-${sys}.json" (builtins.toJSON homeEvalRecords);
                };

              checkedDiagnosticsOutputs =
                if builtins.isAttrs diagnosticsOutputs then
                  diagnosticsOutputs
                else
                  throw "outputs.diagnostics 必须是属性集";
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
                perHostModuleGraph = checkedDiagnosticsOutputs.perHostModuleGraph or true;
              };
              invalidDiagnosticValues = lib.filter (
                name: !builtins.isBool diagnostics.${name}
              ) supportedDiagnosticKeys;
              checkedDiagnostics =
                if invalidDiagnosticKeys != [ ] then
                  throw "outputs.diagnostics 包含不支持的字段：${lib.concatStringsSep ", " invalidDiagnosticKeys}"
                else if invalidDiagnosticValues != [ ] then
                  throw "outputs.diagnostics 的字段必须是布尔值：${lib.concatStringsSep ", " invalidDiagnosticValues}"
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
                discoverySpecVersion = "1.1";
                frameworkVersion = version.string;
                system = sys;
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
              dotCheck = pkgs.runCommand "cloud-module-graph-dot-${sys}" { } ''
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
              reservedCollision = lib.findFirst (name: lib.hasPrefix "cloud-" name) null discoveredUserChecks;
            in
            if reservedCollision != null then
              throw ''
                error: reserved output name

                'checks.${reservedCollision}' 使用了框架保留的 cloud- 前缀
                hint: use a different name for your check
              ''
            else
              assert checkedDiagnostics;
              discoveredChecks.${sys}
              // expectedChecks
              // evalChecks
              // lib.optionalAttrs diagnostics.discovery {
                cloud-discovery = pkgs.writeText "cloud-discovery-${sys}.json" (builtins.toJSON report);
              }
              // lib.optionalAttrs diagnostics.moduleGraph {
                cloud-module-graph-dot = dotCheck;
              }
          );

          moduleOutput = paths: { imports = paths; };
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
      inherit sops';
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
    }).mkFlake
      (
        builtins.removeAttrs args [
          "inputs"
          "moduleRegistries"
          "moduleGroups"
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
