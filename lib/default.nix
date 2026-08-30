{ lib }:

let
  fs = import ./fs.nix { inherit lib; };
  patches = import ./patches.nix;

  defaultSystems = [
    "x86_64-linux"
    "aarch64-linux"
  ];

  forAllSystems = systems: f: lib.genAttrs systems f;

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
        inherit patches;
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

      frameworkMetadataKeys = [
        "role"
        "roles"
        "embedHomeManager"
        "homeManagerUseGlobalPkgs"
        "homeManager"
      ];
      stripMeta =
        hostRaw:
        if builtins.isFunction hostRaw then
          lib.setFunctionArgs (args: builtins.removeAttrs (hostRaw args) frameworkMetadataKeys) (
            builtins.functionArgs hostRaw
          )
        else
          builtins.removeAttrs hostRaw frameworkMetadataKeys;

      mkSystem =
        {
          host,
          system ? null,
          modules ? [ ],
          extraModules ? [ ],
          extraNixosModules ? [ ],
          extraHomeModules ? [ ],
          extraSpecialArgs ? { },
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
          users = usersForHost host;

          metadata = hostMeta.hostMetadataFor { inherit host pkgs; };
          inherit (metadata) roles;
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

          hostMod = stripMeta (import hostModule);
          hostModules =
            filterRoles roles discovered.localAutoModules.nixos
            ++ discovered.registryModules.nixos
            ++ [ hostMod ];

          embedModule = _: {
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
              extraSpecialArgs = specialArgs;
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
            };
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
        in
        hmLib.homeManagerConfiguration {
          inherit pkgs;
          extraSpecialArgs = specialArgsFor extraSpecialArgs;
          modules = [
            optionsCloudHome
          ]
          ++ homeModulesFor { inherit user host roles; }
          ++ modules
          ++ extraModules
          ++ extraHomeModules;
        };

      mkFlake =
        {
          systems ? defaultSystems,
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
          ...
        }:
        let
          nixosConfigurations = lib.listToAttrs (
            map (
              h:
              lib.nameValuePair h.name (mkSystem {
                host = h.name;
                inherit (h) system;
                inherit
                  extraSpecialArgs
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
                      inherit
                        extraSpecialArgs
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
                        inherit
                          host
                          extraSpecialArgs
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
                report = {
                  hosts = map (host: host.name) discovered.hosts;
                  homes = builtins.attrNames homeConfigurations;
                  packages = builtins.attrNames packages.${sys};
                  apps = if appsEnabled then builtins.attrNames apps.${sys} else [ ];
                  nixosModules = builtins.attrNames discovered.localGroupedModules.nixos;
                  homeModules = builtins.attrNames discovered.localGroupedModules.home;
                };
              in
              discoveredChecks.${sys}
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
    ;
  inherit (fs) importModules flattenTree groupModules;
  inherit patches;
}
