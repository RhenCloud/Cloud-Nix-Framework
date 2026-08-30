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
            map
              (d: {
                dir = d.name;
                path = projectRoot + "/packages/" + d.name + "/default.nix";
              })
              (
                lib.filter (d: builtins.pathExists (projectRoot + "/packages/" + d.name + "/default.nix")) (
                  onlyDirs (listDirAt "packages")
                )
              );

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

          apps =
            map
              (d: {
                inherit (d) name;
                path = projectRoot + "/apps/" + d.name + "/default.nix";
              })
              (
                lib.filter (d: builtins.pathExists (projectRoot + "/apps/" + d.name + "/default.nix")) (
                  onlyDirs (listDirAt "apps")
                )
              );

          formatter =
            let
              path = projectRoot + "/formatter/default.nix";
            in
            if builtins.pathExists path then path else null;

          deploy =
            let
              path = projectRoot + "/deploy/default.nix";
            in
            if builtins.pathExists path then path else null;

          shells =
            map
              (d: {
                inherit (d) name;
                path = projectRoot + "/shells/" + d.name + "/default.nix";
              })
              (
                lib.filter (d: builtins.pathExists (projectRoot + "/shells/" + d.name + "/default.nix")) (
                  onlyDirs (listDirAt "shells")
                )
              );

          checks =
            map
              (d: {
                inherit (d) name;
                path = projectRoot + "/checks/" + d.name + "/default.nix";
              })
              (
                lib.filter (d: builtins.pathExists (projectRoot + "/checks/" + d.name + "/default.nix")) (
                  onlyDirs (listDirAt "checks")
                )
              );

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

      rolesFromModule =
        mod:
        let
          fromConfig =
            if
              builtins.isAttrs mod
              && mod ? config
              && builtins.isAttrs mod.config
              && !(builtins.isFunction mod.config)
            then
              mod.config.cloud.roles or mod.config.cloud.role or null
            else
              null;
        in
        normalizeRoles (mod.roles or mod.role or fromConfig);

      rolesFor =
        {
          host,
          pkgs,
        }:
        let
          hostRec = resolveHost host;
          modPath = projectRoot + "/hosts/" + hostRec.dir + "/default.nix";
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
              imported = import modPath;
              mod = if builtins.isFunction imported then imported hostArgs else imported;
            in
            rolesFromModule mod
          );
        in
        if attempt.success then attempt.value else null;

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
          pkgs,
          host ? null,
        }:
        let
          roles = if host == null then null else rolesFor { inherit host pkgs; };
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
        }:
        let
          hostRecord = resolveHost host;
          sys = if system == null then hostRecord.system else system;
          pkgs = pkgsFor {
            system = sys;
            inherit nixpkgsConfig extraOverlays;
          };
          hostModule = projectRoot + "/hosts/" + hostRecord.dir + "/default.nix";
          specialArgs = specialArgsFor extraSpecialArgs;
          users = usersForHost host;

          hostRaw = import hostModule;
          roles = rolesFor { inherit host pkgs; };
          hostMod =
            if builtins.isFunction hostRaw then
              lib.setFunctionArgs (
                args:
                builtins.removeAttrs (hostRaw args) [
                  "role"
                  "roles"
                ]
              ) (builtins.functionArgs hostRaw)
            else
              builtins.removeAttrs hostRaw [
                "role"
                "roles"
              ];

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
              useGlobalPkgs = true;
              useUserPackages = true;
              extraSpecialArgs = specialArgs;
              users = lib.genAttrs users (u: {
                imports =
                  homeModulesFor {
                    user = u;
                    inherit host pkgs;
                  }
                  ++ extraModules
                  ++ extraHomeModules;
              });
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
          ++ lib.optionals (embedHomeManager && users != [ ]) [ embedModule ]
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
        in
        hmLib.homeManagerConfiguration {
          inherit pkgs;
          extraSpecialArgs = specialArgsFor extraSpecialArgs;
          modules = [
            optionsCloudHome
          ]
          ++ homeModulesFor { inherit user host pkgs; }
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
                  ;
              })
            ) discovered.hosts
          );

          packageDefs = map (
            p:
            let
              parts = lib.splitString "." p.dir;
              last = lib.last parts;
              singleSystem = lib.elem last systems;
              name = if singleSystem then lib.concatStringsSep "." (lib.init parts) else p.dir;
            in
            {
              inherit (p) path;
              inherit name;
              system = if singleSystem then last else null;
            }
          ) discovered.packages;

          packages = forAllSystems systems (
            sys:
            let
              pkgs = pkgsFor {
                system = sys;
                inherit nixpkgsConfig extraOverlays;
              };
            in
            lib.listToAttrs (
              lib.concatMap (
                p:
                if p.system == null || p.system == sys then
                  [ (lib.nameValuePair p.name (callPackage pkgs p.path)) ]
                else
                  [ ]
              ) packageDefs
            )
          );

          devShells = forAllSystems systems (
            sys:
            let
              pkgs = pkgsFor {
                system = sys;
                inherit nixpkgsConfig extraOverlays;
              };
            in
            lib.listToAttrs (map (s: lib.nameValuePair s.name (callPackage pkgs s.path)) discovered.shells)
          );

          checks = forAllSystems systems (
            sys:
            let
              pkgs = pkgsFor {
                system = sys;
                inherit nixpkgsConfig extraOverlays;
              };
            in
            lib.listToAttrs (map (s: lib.nameValuePair s.name (callPackage pkgs s.path)) discovered.checks)
          );

          apps = forAllSystems systems (
            sys:
            let
              pkgs = pkgsFor {
                system = sys;
                inherit nixpkgsConfig extraOverlays;
              };
            in
            lib.listToAttrs (map (a: lib.nameValuePair a.name (callPackage pkgs a.path)) discovered.apps)
          );

          formatter = forAllSystems systems (
            sys:
            let
              pkgs = pkgsFor {
                system = sys;
                inherit nixpkgsConfig extraOverlays;
              };
            in
            callPackage pkgs discovered.formatter
          );

          deploy = importFile discovered.deploy;

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
          // lib.optionalAttrs (discovered.apps != [ ]) { inherit apps; }
          // lib.optionalAttrs (discovered.formatter != null) { inherit formatter; }
          // lib.optionalAttrs (discovered.deploy != null) { inherit deploy; };
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
