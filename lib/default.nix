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
  moduleTools = import ./internal/modules.nix { inherit lib; };

  defaultSystems = [
    "x86_64-linux"
    "aarch64-linux"
  ];

  forAllSystems = systems: f: lib.genAttrs systems f;

  version = {
    major = 0;
    minor = 4;
    patch = 0;
    pre = "dev";
    string = "0.4.0-dev";
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
      root ? null,
    }:
    let
      self = inputs.self or (throw "Cloud Nix Framework 需要 inputs.self");
      nixpkgs = inputs.nixpkgs or (throw "Cloud Nix Framework 需要 inputs.nixpkgs");
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
          ;
      };

      hostMeta = import ./host.nix {
        inherit lib discovered;
      };

      sops' = import ./sops.nix { inherit projectRoot; };
      cloudInject = {
        inherit patches version;
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

      usersForHost = host: map (h: h.user) (lib.filter (h: lib.elem host h.hosts) discovered.homes);

      relUnderModules = p: lib.last (lib.splitString "/modules/" p);
      isDefaultFile = p: baseNameOf p == "default.nix";
      isCommon = p: lib.hasPrefix "_" (lib.head (lib.splitString "/" (relUnderModules p)));
      roleOfPath = p: lib.head (lib.splitString "/" (relUnderModules p));
      filterRoles =
        roles: paths:
        lib.filter (
          p: isDefaultFile p || isCommon p || roles == null || lib.elem (roleOfPath p) roles
        ) paths;

      applyModuleOverridesToPath =
        { overrideMap, paths }:
        if overrideMap == { } then
          paths
        else
          moduleTools.applyModuleOverrides {
            overrides = overrideMap;
            modules = paths;
          };

      homeModulesFor =
        {
          user,
          host ? null,
          roles ? null,
        }:
        let
          ownDefault = lib.filter builtins.pathExists [ (projectRoot + "/homes/" + user + "/default.nix") ];
          ownHost =
            if host == null then
              [ ]
            else
              lib.filter builtins.pathExists [ (projectRoot + "/homes/" + user + "/" + host + ".nix") ];
        in
        filterRoles roles discovered.localAutoModules.home
        ++ discovered.registryModules.home
        ++ ownDefault
        ++ ownHost;

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
        }:
        let
          hostRecord = hostMeta.resolveHost host;
          sys = if system == null then hostRecord.system else system;
          pkgs = pkgsFor {
            system = sys;
            inherit nixpkgsConfig extraOverlays;
          };
          hostModule = hostRecord.path;
          specialArgs = specialArgsFor extraSpecialArgs;
          homeSpecialArgs = specialArgsFor extraHomeSpecialArgs;
          users = usersForHost host;

          metadata = hostMeta.hostMetadataFor { inherit host pkgs; };
          inherit (metadata) roles modules;
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

          validatedModuleOverrides = moduleTools.validateModuleOverrides modules;

          hostMod = import hostModule;
          hostModules =
            let
              baseModules =
                filterRoles roles discovered.localAutoModules.nixos
                ++ discovered.registryModules.nixos
                ++ [ hostMod ];
            in
            applyModuleOverridesToPath {
              overrideMap = validatedModuleOverrides;
              paths = baseModules;
            };

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
                        inherit host roles;
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
          pkgs = pkgsFor {
            system = sys;
            inherit nixpkgsConfig extraOverlays;
          };
          roles = if host == null then null else hostMeta.rolesFor { inherit host pkgs; };
          metadata = if host == null then null else hostMeta.hostMetadataFor { inherit host pkgs; };
          validatedModuleOverridesHome =
            if metadata == null then { } else moduleTools.validateModuleOverrides metadata.modules;
        in
        hmLib.homeManagerConfiguration {
          inherit pkgs;
          extraSpecialArgs = specialArgsFor extraSpecialArgs;
          modules = [
            optionsCloudHome
          ]
          ++ (
            let
              baseHomeModules = homeModulesFor { inherit user host roles; };
            in
            if validatedModuleOverridesHome == { } then
              baseHomeModules
            else
              applyModuleOverridesToPath {
                overrideMap = validatedModuleOverridesHome;
                paths = baseHomeModules;
              }
          )
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
              })
            ) discovered.hosts
          );

          disabledByName =
            kind: name:
            if builtins.isList disabledOutputs then
              lib.elem "${kind}.${name}" disabledOutputs
              || (kind == "formatter" && name == "default" && lib.elem "formatter" disabledOutputs)
              || (kind == "deploy" && name == "default" && lib.elem "deploy" disabledOutputs)
            else if builtins.isAttrs disabledOutputs then
              lib.elem name (disabledOutputs.${kind} or [ ])
            else
              throw "disabledOutputs 必须是字符串列表或 output 名到名称列表的属性集";

          disabledForSystem =
            kind: name: system:
            disabledByName kind name
            || (
              if builtins.isList disabledOutputs then
                lib.elem "${kind}.${system}.${name}" disabledOutputs
                || (kind == "formatter" && name == "default" && lib.elem "formatter.${system}" disabledOutputs)
              else
                lib.elem "${system}.${name}" (disabledOutputs.${kind} or [ ])
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
              throw "${kind}.${name} 的 meta.enable 必须是布尔值"
            else if
              supportedSystems != null
              && !(builtins.isList supportedSystems && lib.all builtins.isString supportedSystems)
            then
              throw "${kind}.${name} 的 meta.systems 必须是字符串列表"
            else
              enabled
              && (supportedSystems == null || lib.elem system supportedSystems)
              && !disabledForSystem kind name system;

          uniqueDefinitions =
            kind: system: definitions:
            let
              names = map (d: d.name) definitions;
              duplicates = lib.unique (lib.filter (n: lib.count (c: c == n) names > 1) names);
            in
            if duplicates == [ ] then
              definitions
            else
              throw "${kind}.${system} 存在重复名称：${lib.concatStringsSep ", " duplicates}";

          knownSystems = lib.unique (systems ++ lib.systems.flakeExposed);
          packageDefs = map (
            package:
            let
              parts = lib.splitString "." package.name;
              suffix = lib.last parts;
              hasExplicitMetadata = package.meta ? systems;
              legacySystem =
                if package.explicitSystem == null && !hasExplicitMetadata && lib.elem suffix knownSystems then
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
              pkgs = pkgsFor {
                system = sys;
                inherit nixpkgsConfig extraOverlays;
              };
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
                pkgs = pkgsFor {
                  system = sys;
                  inherit nixpkgsConfig extraOverlays;
                };
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
                  pkgs = pkgsFor {
                    system = sys;
                    inherit nixpkgsConfig extraOverlays;
                  };
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
              throw "deploy 的 meta.enable 必须是布尔值"
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
                map
                  (
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
                    })
                  )
                  (
                    lib.filter (
                      h: builtins.pathExists (projectRoot + "/homes/" + h.user + "/default.nix")
                    ) discovered.homes
                  )
              );
              perHost = lib.listToAttrs (
                lib.concatMap (
                  h:
                  map
                    (
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
                      })
                    )
                    (
                      lib.filter (
                        host:
                        builtins.pathExists (projectRoot + "/homes/" + h.user + "/" + host + ".nix")
                        && lib.any (x: x.name == host) discovered.hosts
                      ) h.hosts
                    )
                ) discovered.homes
              );
            in
            global // perHost;

          images = lib.mapAttrs (
            host: cfg:
            let
              hostRec = hostMeta.resolveHost host;
              fmts = hostRec.meta.images.formats or cfg.config.cloud.images.formats;
              avail = cfg.config.system.build.images;
            in
            lib.genAttrs fmts (
              f:
              if builtins.hasAttr f avail then
                avail.${f}
              else
                throw "主机 '${host}' 请求镜像格式 '${f}'，但当前 nixpkgs 无此变体；可用变体见 `nixos-rebuild build-image` 列表"
            )
          ) nixosConfigurations;

          checks = forAllSystems systems (
            sys:
            if builtins.hasAttr "cloud-discovery" discoveredChecks.${sys} then
              throw "checks.cloud-discovery 是框架保留名称"
            else
              let
                pkgs = pkgsFor {
                  system = sys;
                  inherit nixpkgsConfig extraOverlays;
                };
                discoveredHosts = map (host: host.name) discovered.hosts;
                discoveredHomes = builtins.attrNames homeConfigurations;
                discoveredPkgs = builtins.attrNames packages.${sys};
                discoveredApps = if appsEnabled then builtins.attrNames apps.${sys} else [ ];
                report = {
                  hosts = discoveredHosts;
                  homes = discoveredHomes;
                  packages = discoveredPkgs;
                  apps = discoveredApps;
                  nixosModules = builtins.attrNames discovered.localGroupedModules.nixos;
                  homeModules = builtins.attrNames discovered.localGroupedModules.home;
                };
                checkExpected =
                  kind: expected: actual:
                  let
                    missing = lib.filter (x: !lib.elem x actual) expected;
                    script = pkgs.writeShellScript "check-discovery-${kind}-${sys}" ''
                      set -euo pipefail
                      missing=${lib.escapeShellArg (builtins.toJSON missing)}
                      if [ "$missing" != "[]" ]; then
                        echo "cloud-discovery: expectedOutputs.${kind} 缺少以下项目："
                        echo "$missing" | ${pkgs.jq}/bin/jq -r '.[]' | sed 's/^/  - /'
                        exit 1
                      fi
                      echo "cloud-discovery: ${kind} OK"
                    '';
                  in
                  pkgs.runCommand "cloud-discovery-check-${kind}-${sys}" { } "bash ${script} && touch $out";
                expectedChecks = lib.concatLists (
                  lib.mapAttrsToList (
                    kind: expected:
                    let
                      actual =
                        if kind == "hosts" then
                          discoveredHosts
                        else if kind == "homes" then
                          discoveredHomes
                        else if kind == "packages" then
                          discoveredPkgs
                        else if kind == "apps" then
                          discoveredApps
                        else
                          throw "expectedOutputs 不支持字段 '${kind}'，可用：hosts, homes, packages, apps";
                    in
                    [ (lib.nameValuePair "cloud-discovery-expected-${kind}" (checkExpected kind expected actual)) ]
                  ) expectedOutputs
                );
              in
              discoveredChecks.${sys}
              // lib.listToAttrs expectedChecks
              // {
                cloud-discovery = pkgs.writeText "cloud-discovery-${sys}.json" (builtins.toJSON report);
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
      inherit patches;
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
    }).mkFlake
      (
        builtins.removeAttrs args [
          "inputs"
          "moduleRegistries"
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
}
