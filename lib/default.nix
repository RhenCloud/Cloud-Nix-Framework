{
  lib,
}:

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
    {
      lib,
      ...
    }:
    {
      options.cloud = {
        users = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [ ];
        };
        images = lib.mkOption {
          type = lib.types.submodule {
            options.formats = lib.mkOption {
              type = lib.types.listOf lib.types.str;
              default = [ ];
              description = "需要生成的镜像变体列表，对应 nixpkgs 的 image.modules 变体名（如 iso、raw、oci 等）";
            };
          };
          default = { };
          description = "镜像生成配置，由框架映射为 `images.<host>.<format>` 输出";
        };
      };
    };

  optionsCloudHome =
    {
      lib,
      ...
    }:
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
      channels = {
        inherit nixpkgs;
      };

      listDirAt =
        rel:
        if builtins.pathExists (projectRoot + "/" + rel) then fs.listDir (projectRoot + "/" + rel) else [ ];
      onlyDirs = es: lib.filter (e: e.type == "directory") es;
      onlyFiles = es: lib.filter (e: e.type == "regular") es;
      nixFiles = es: lib.filter (e: lib.hasSuffix ".nix" e.name) (onlyFiles es);
      readMetadata =
        path:
        if !builtins.pathExists path then
          { }
        else
          let
            value = import path;
          in
          if builtins.isAttrs value && !builtins.isFunction value then
            value
          else
            throw "元数据文件 '${toString path}' 必须直接返回属性集";
      namedOutputsAt =
        dir:
        map
          (d: {
            inherit (d) name;
            path = projectRoot + "/${dir}/" + d.name + "/default.nix";
            meta = readMetadata (projectRoot + "/${dir}/" + d.name + "/meta.nix");
          })
          (
            lib.filter (d: builtins.pathExists (projectRoot + "/${dir}/" + d.name + "/default.nix")) (
              onlyDirs (listDirAt dir)
            )
          );

      discovered =
        let
          localGroupedModules =
            if builtins.pathExists (projectRoot + "/modules") then
              fs.groupModules (projectRoot + "/modules")
            else
              {
                nixos = { };
                home = { };
              };
          localAutoModules = {
            nixos = lib.concatLists (lib.attrValues localGroupedModules.nixos);
            home = lib.concatLists (lib.attrValues localGroupedModules.home);
          };
          registryModules =
            lib.foldl
              (acc: r: {
                nixos = acc.nixos ++ (r.modules.nixos or [ ]);
                home = acc.home ++ (r.modules.home or [ ]);
              })
              {
                nixos = [ ];
                home = [ ];
              }
              moduleRegistries;
        in
        {
          inherit localAutoModules localGroupedModules registryModules;

          hosts = map (
            e:
            let
              parts = lib.splitString "." e.name;
            in
            {
              dir = e.name;
              name = lib.concatStringsSep "." (lib.init parts);
              system = lib.last parts;
              path = projectRoot + "/hosts/" + e.name + "/default.nix";
              metaPath = projectRoot + "/hosts/" + e.name + "/meta.nix";
            }
          ) (onlyDirs (listDirAt "hosts"));

          homes = map (d: {
            user = d.name;
            hosts = lib.filter (f: f != null) (
              map (f: if f.name == "default.nix" then null else lib.removeSuffix ".nix" f.name) (
                nixFiles (listDirAt ("homes/" + d.name))
              )
            );
          }) (onlyDirs (listDirAt "homes"));

          packages =
            let
              roots = onlyDirs (listDirAt "packages");
              direct =
                map
                  (d: {
                    inherit (d) name;
                    path = projectRoot + "/packages/" + d.name + "/default.nix";
                    meta = readMetadata (projectRoot + "/packages/" + d.name + "/meta.nix");
                    explicitSystem = null;
                  })
                  (lib.filter (d: builtins.pathExists (projectRoot + "/packages/" + d.name + "/default.nix")) roots);
              systemFirst = lib.concatMap (
                systemDir:
                if builtins.pathExists (projectRoot + "/packages/" + systemDir.name + "/default.nix") then
                  [ ]
                else
                  map
                    (d: {
                      inherit (d) name;
                      path = projectRoot + "/packages/" + systemDir.name + "/" + d.name + "/default.nix";
                      meta = readMetadata (projectRoot + "/packages/" + systemDir.name + "/" + d.name + "/meta.nix");
                      explicitSystem = systemDir.name;
                    })
                    (
                      lib.filter (
                        d: builtins.pathExists (projectRoot + "/packages/" + systemDir.name + "/" + d.name + "/default.nix")
                      ) (onlyDirs (listDirAt ("packages/" + systemDir.name)))
                    )
              ) roots;
            in
            direct ++ systemFirst;

          overlays =
            map
              (d: {
                inherit (d) name;
                path = projectRoot + "/overlays/" + d.name + "/default.nix";
              })
              (
                lib.filter (d: builtins.pathExists (projectRoot + "/overlays/" + d.name + "/default.nix")) (
                  onlyDirs (listDirAt "overlays")
                )
              );

          apps = namedOutputsAt "apps";

          formatter =
            let
              path = projectRoot + "/formatter/default.nix";
            in
            if builtins.pathExists path then
              {
                inherit path;
                meta = readMetadata (projectRoot + "/formatter/meta.nix");
              }
            else
              null;

          deploy =
            let
              path = projectRoot + "/deploy/default.nix";
            in
            if builtins.pathExists path then
              {
                inherit path;
                meta = readMetadata (projectRoot + "/deploy/meta.nix");
              }
            else
              null;

          shells = namedOutputsAt "shells";

          checks = namedOutputsAt "checks";

          libFiles = nixFiles (listDirAt "lib");

        };

      importFile =
        path:
        let
          imported = import path;
          declared = if builtins.isFunction imported then builtins.functionArgs imported else { };
          args = builtins.intersectAttrs declared {
            inherit
              lib
              self
              inputs
              cloud
              ;
          };
        in
        if builtins.isFunction imported then imported args else imported;

      sops' = rec {
        commonFile = projectRoot + "/secrets/common.yaml";
        hostFile = host: projectRoot + "/secrets/hosts/${host}.yaml";
        defaultFile = host: if host == null then commonFile else hostFile host;
        secret =
          {
            source,
            host ? null,
            name ? null,
          }:
          let
            options = {
              sopsFile =
                if source == "common" then
                  commonFile
                else if source == "host" && host != null then
                  hostFile host
                else if source == "host" then
                  throw "cloud.sops.secret 使用 source = \"host\" 时必须传入 host"
                else
                  throw "cloud.sops.secret.source 必须是 \"common\" 或 \"host\"";
            };
          in
          if name == null then
            options
          else if builtins.isString name && name != "" then
            {
              sops.secrets.${name} = options;
            }
          else
            throw "cloud.sops.secret.name 必须是非空字符串";
        mkModule =
          {
            sopsNixModule,
            host ? null,
            defaultSopsFile ? defaultFile host,
          }:
          {
            ...
          }:
          {
            imports = [ sopsNixModule ];
            sops = {
              defaultSopsFormat = "yaml";
              inherit defaultSopsFile;
            };
          };
      };

      cloudInject = {
        inherit patches;
        sops = sops';
      };
      cloud = cloudInject;

      overlays = lib.listToAttrs (
        map (
          o: lib.nameValuePair o.name ((import o.path) { inherit inputs self cloud; })
        ) discovered.overlays
      );
      overlayList = lib.attrValues overlays;

      pkgsFor =
        {
          system,
          nixpkgsConfig ? { },
          extraOverlays ? [ ],
        }:
        import nixpkgs.outPath {
          inherit system;
          config = nixpkgsConfig;
          overlays = overlayList ++ extraOverlays;
        };

      resolveHost =
        host:
        let
          matches = lib.filter (h: h.name == host) discovered.hosts;
        in
        if matches == [ ] then
          throw "未发现主机 '${host}'，请在 hosts/${host}.<system>/ 下创建 default.nix"
        else
          lib.head matches;

      normalizeRoles =
        roles:
        if roles == null then
          null
        else if builtins.isString roles then
          [ roles ]
        else if builtins.isList roles && lib.all builtins.isString roles then
          roles
        else
          throw "主机 role/roles 必须是字符串或字符串列表，当前类型为 ${builtins.typeOf roles}";

      normalizeHostMetadata =
        raw:
        let
          homeManagerMeta = raw.homeManager or { };
          fromConfig =
            if raw ? config && builtins.isAttrs raw.config && !(builtins.isFunction raw.config) then
              raw.config.cloud.roles or raw.config.cloud.role or null
            else
              null;
        in
        {
          roles = normalizeRoles (raw.roles or raw.role or fromConfig);
          embedHomeManager = raw.embedHomeManager or homeManagerMeta.embed or null;
          homeManagerUseGlobalPkgs = raw.homeManagerUseGlobalPkgs or homeManagerMeta.useGlobalPkgs or null;
        };

      hostMetadataFor =
        {
          host,
          pkgs,
        }:
        let
          hostRec = resolveHost host;
        in
        if builtins.pathExists hostRec.metaPath then
          normalizeHostMetadata (readMetadata hostRec.metaPath)
        else
          let
            hostArgs = {
              inherit
                lib
                self
                inputs
                pkgs
                ;
              config = null;
              options = null;
              modules = null;
              name = null;
            };
            attempt = builtins.tryEval (
              let
                imported = import hostRec.path;
                mod = if builtins.isFunction imported then imported hostArgs else imported;
                metadata = normalizeHostMetadata mod;
              in
              builtins.deepSeq metadata metadata
            );
          in
          if attempt.success then
            attempt.value
          else
            builtins.trace "警告：主机 '${host}' 的旧式顶层元数据探测失败，角色过滤已关闭；请迁移到 hosts/${hostRec.dir}/meta.nix" (
              normalizeHostMetadata { }
            );

      resolveHostPolicy =
        {
          name,
          value,
          host,
          default,
        }:
        let
          resolved =
            if builtins.isBool value then
              value
            else if builtins.isFunction value then
              value host
            else if builtins.isAttrs value && value ? hosts then
              value.hosts.${host} or value.default or default
            else if builtins.isAttrs value then
              value.${host} or value.default or default
            else
              throw "${name} 必须是布尔值、host -> bool 函数或 per-host 属性集";
        in
        if builtins.isBool resolved then resolved else throw "${name} 为主机 '${host}' 解析出的值必须是布尔值";

      hostPolicyFromMetadata =
        {
          metadata,
          key,
          fallback,
          host,
        }:
        let
          value = metadata.${key};
        in
        if value == null then
          fallback
        else if builtins.isBool value then
          value
        else
          throw "主机 '${host}' 的 ${key} 元数据必须是布尔值";

      rolesFor =
        {
          host,
          pkgs,
        }:
        (hostMetadataFor { inherit host pkgs; }).roles;

      relUnderModules = p: lib.removePrefix (projectRoot + "/modules/") p;
      roleOfPath = p: lib.head (lib.splitString "/" (relUnderModules p));
      isDefaultFile = p: baseNameOf p == "default.nix";
      isCommon = p: lib.hasPrefix "_" (roleOfPath p);
      filterRoles =
        roles: paths:
        lib.filter (
          p: isDefaultFile p || isCommon p || roles == null || lib.elem (roleOfPath p) roles
        ) paths;

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

      callPackage =
        pkgs: path:
        let
          fn = import path;
          declared = builtins.functionArgs fn;
          extras = lib.intersectAttrs declared {
            inherit inputs self cloud;
          };
        in
        pkgs.callPackage fn extras;

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
          hostRecord = resolveHost host;
          sys = if system == null then hostRecord.system else system;
          pkgs = pkgsFor {
            system = sys;
            inherit nixpkgsConfig extraOverlays;
          };
          hostModule = hostRecord.path;
          specialArgs = specialArgsFor extraSpecialArgs;
          users = usersForHost host;

          metadata = hostMetadataFor { inherit host pkgs; };
          inherit (metadata) roles;
          embedForHost = hostPolicyFromMetadata {
            inherit metadata host;
            key = "embedHomeManager";
            fallback = resolveHostPolicy {
              name = "embedHomeManager";
              value = embedHomeManager;
              inherit host;
              default = true;
            };
          };
          useGlobalPkgs = hostPolicyFromMetadata {
            inherit metadata host;
            key = "homeManagerUseGlobalPkgs";
            fallback = resolveHostPolicy {
              name = "homeManagerUseGlobalPkgs";
              inherit host;
              value = homeManagerUseGlobalPkgs;
              default = true;
            };
          };
          frameworkMetadataKeys = [
            "role"
            "roles"
            "embedHomeManager"
            "homeManagerUseGlobalPkgs"
            "homeManager"
          ];
          hostRaw = import hostModule;
          hostMod =
            if builtins.isFunction hostRaw then
              lib.setFunctionArgs (args: builtins.removeAttrs (hostRaw args) frameworkMetadataKeys) (
                builtins.functionArgs hostRaw
              )
            else
              builtins.removeAttrs hostRaw frameworkMetadataKeys;

          hostModules =
            filterRoles roles discovered.localAutoModules.nixos
            ++ discovered.registryModules.nixos
            ++ [ hostMod ];

          embedModule = _: {
            imports = [
              (
                if hm == null then
                  throw "主机 '${host}' 关联了 home（${lib.concatStringsSep ", " users}），但缺少 home-manager input，请在 flake inputs 中 follows"
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

          setCloudModule = _: {
            config.cloud.users = users;
          };

          finalModules = [
            optionsCloud
            setCloudModule
            (_: {
              nixpkgs = {
                inherit pkgs;
              };
            })
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
              (resolveHost host).system
            else if system != null then
              system
            else
              lib.head defaultSystems;
          pkgs = pkgsFor {
            system = sys;
            inherit nixpkgsConfig extraOverlays;
          };
          roles = if host == null then null else rolesFor { inherit host pkgs; };
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
              names = map (definition: definition.name) definitions;
              duplicates = lib.unique (
                lib.filter (name: lib.count (candidate: candidate == name) names > 1) names
              );
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
            lib.listToAttrs (
              map (package: lib.nameValuePair package.name (callPackage pkgs package.path)) definitions
            )
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
                  definition:
                  metadataEnabled {
                    inherit kind;
                    inherit (definition) name meta;
                    system = sys;
                  }
                ) definitions;
              in
              lib.listToAttrs (
                map (definition: lib.nameValuePair definition.name (callPackage pkgs definition.path)) enabled
              )
            );

          devShells = namedSystemOutputs "devShells" discovered.shells;
          discoveredChecks = namedSystemOutputs "checks" discovered.checks;
          apps = namedSystemOutputs "apps" discovered.apps;
          appsEnabled = lib.any (system: apps.${system} != { }) systems;

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
              fmts = cfg.config.cloud.images.formats;
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
      inherit mkFlake;
      inherit mkSystem;
      inherit mkHome;
      inherit forAllSystems;
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
  inherit mkLib;
  inherit mkFlake;
  inherit forAllSystems;
  inherit renderOptions;
  inherit (fs) importModules flattenTree groupModules;
  inherit patches;
}
