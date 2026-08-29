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
    }:
    let
      self = inputs.self or (throw "Cloud Nix Framework 需要 inputs.self");
      nixpkgs = inputs.nixpkgs or (throw "Cloud Nix Framework 需要 inputs.nixpkgs");
      nixosSystem = nixpkgs.lib.nixosSystem;
      hm = inputs.home-manager or null;
      root = toString self.outPath;
      channels = {
        inherit nixpkgs;
      };

      listDirAt =
        rel: if builtins.pathExists (root + "/" + rel) then fs.listDir (root + "/" + rel) else [ ];
      onlyDirs = es: lib.filter (e: e.type == "directory") es;
      onlyFiles = es: lib.filter (e: e.type == "regular") es;
      nixFiles = es: lib.filter (e: lib.hasSuffix ".nix" e.name) (onlyFiles es);

      discovered =
        let
          localAutoModules =
            if builtins.pathExists (root + "/modules") then
              fs.importModules (root + "/modules")
            else
              {
                nixos = [ ];
                home = [ ];
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
          autoModules = {
            nixos = registryModules.nixos ++ localAutoModules.nixos;
            home = registryModules.home ++ localAutoModules.home;
          };
        in
        {
          inherit localAutoModules registryModules;

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
                path = root + "/packages/" + d.name + "/default.nix";
              })
              (
                lib.filter (d: builtins.pathExists (root + "/packages/" + d.name + "/default.nix")) (
                  onlyDirs (listDirAt "packages")
                )
              );

          overlays =
            map
              (d: {
                inherit (d) name;
                path = root + "/overlays/" + d.name + "/default.nix";
              })
              (
                lib.filter (d: builtins.pathExists (root + "/overlays/" + d.name + "/default.nix")) (
                  onlyDirs (listDirAt "overlays")
                )
              );

          shells =
            map
              (d: {
                inherit (d) name;
                path = root + "/shells/" + d.name + "/default.nix";
              })
              (
                lib.filter (d: builtins.pathExists (root + "/shells/" + d.name + "/default.nix")) (
                  onlyDirs (listDirAt "shells")
                )
              );

          checks =
            map
              (d: {
                inherit (d) name;
                path = root + "/checks/" + d.name + "/default.nix";
              })
              (
                lib.filter (d: builtins.pathExists (root + "/checks/" + d.name + "/default.nix")) (
                  onlyDirs (listDirAt "checks")
                )
              );

          libFiles = nixFiles (listDirAt "lib");

          inherit autoModules;
        };

      importFile =
        path:
        let
          imported = import path;
          declared = if builtins.isFunction imported then builtins.functionArgs imported else { };
          args = builtins.intersectAttrs declared {
            inherit lib self inputs;
          };
        in
        if builtins.isFunction imported then imported args else imported;

      sops' = rec {
        commonFile = root + "/secrets/common.yaml";
        hostFile = host: root + "/secrets/hosts/${host}.yaml";
        mkModule =
          {
            sopsNixModule,
            host ? null,
          }:
          {
            ...
          }:
          {
            imports = [ sopsNixModule ];
            sops = {
              defaultSopsFormat = "yaml";
              defaultSopsFile = if host == null then commonFile else hostFile host;
            };
          };
      };

      cloudInject = {
        inherit patches;
        sops = sops';
      };
      cloud = cloudInject;

      resolveHost =
        host:
        let
          matches = lib.filter (h: h.name == host) discovered.hosts;
        in
        if matches == [ ] then
          throw "未发现主机 '${host}'，请在 hosts/${host}.<system>/ 下创建 default.nix"
        else
          lib.head matches;

      roleFor =
        host:
        let
          hostRec = resolveHost host;
          modPath = root + "/hosts/" + hostRec.dir + "/default.nix";
          hostArgs = {
            inherit lib self inputs;
            pkgs = nixpkgs.legacyPackages.${hostRec.system};
            config = null;
            options = null;
            modules = null;
            name = null;
          };
          attempt = builtins.tryEval (
            let
              imported = import modPath;
              mod = if builtins.isFunction imported then imported hostArgs else imported;
              fromConfig =
                if
                  builtins.isAttrs mod
                  && mod ? config
                  && builtins.isAttrs mod.config
                  && !(builtins.isFunction mod.config)
                then
                  mod.config.cloud.role or null
                else
                  null;
            in
            mod.role or fromConfig
          );
        in
        if attempt.success then attempt.value else null;

      relUnderModules = p: lib.removePrefix (root + "/modules/") p;
      roleOfPath = p: lib.head (lib.splitString "/" (relUnderModules p));
      isDefaultFile = p: baseNameOf p == "default.nix";
      isCommon = p: lib.hasPrefix "_" (roleOfPath p);
      moduleKey = p: lib.replaceStrings [ "/" ] [ "." ] (relUnderModules p);
      filterRole =
        role: paths:
        lib.filter (p: isDefaultFile p || isCommon p || role == null || (roleOfPath p) == role) paths;

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
        }:
        let
          role = if host == null then null else roleFor host;
          ownDefault = lib.filter builtins.pathExists [ (root + "/homes/" + user + "/default.nix") ];
          ownHost =
            if host == null then
              [ ]
            else
              lib.filter builtins.pathExists [ (root + "/homes/" + user + "/" + host + ".nix") ];
        in
        filterRole role discovered.localAutoModules.home
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
          extraSpecialArgs ? { },
        }:
        let
          hostRecord = resolveHost host;
          sys = if system == null then hostRecord.system else system;
          hostModule = root + "/hosts/" + hostRecord.dir + "/default.nix";
          specialArgs = specialArgsFor extraSpecialArgs;
          users = usersForHost host;

          hostArgs = {
            inherit lib self inputs;
            pkgs = nixpkgs.legacyPackages.${hostRecord.system};
            config = null;
            options = null;
            modules = null;
            name = null;
          };
          hostRaw = import hostModule;
          hostCalled = if builtins.isFunction hostRaw then hostRaw hostArgs else hostRaw;
          role = hostCalled.role or null;
          hostMod = builtins.removeAttrs hostCalled [ "role" ];

          hostModules =
            filterRole role discovered.localAutoModules.nixos
            ++ discovered.registryModules.nixos
            ++ [ hostMod ];

          overlays = lib.listToAttrs (
            map (
              o: lib.nameValuePair o.name ((import o.path) { inherit inputs self cloud; })
            ) discovered.overlays
          );
          overlaysModule = _: {
            nixpkgs.overlays = lib.attrValues overlays;
          };

          embedModule =
            {
              ...
            }:
            {
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
                users = lib.genAttrs users (u: {
                  imports = homeModulesFor {
                    user = u;
                    inherit host;
                  };
                  extraSpecialArgs = specialArgs;
                });
              };
            };

          setCloudModule =
            {
              config,
              ...
            }:
            {
              config.cloud.users = users;
            };

          finalModules = [
            optionsCloud
            setCloudModule
          ]
          ++ lib.optionals (discovered.overlays != [ ]) [ overlaysModule ]
          ++ lib.optionals (users != [ ]) [ embedModule ]
          ++ hostModules
          ++ modules
          ++ extraModules
          ++ extraNixosModules;
        in
        nixosSystem {
          system = sys;
          inherit specialArgs;
          modules = finalModules ++ [ { nixpkgs.hostPlatform = sys; } ];
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
          pkgs = nixpkgs.legacyPackages.${sys};
        in
        hmLib.homeManagerConfiguration {
          inherit pkgs;
          extraSpecialArgs = specialArgsFor extraSpecialArgs;
          modules = [
            optionsCloudHome
          ]
          ++ homeModulesFor { inherit user host; }
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
          ...
        }:
        let
          nixosConfigurations = lib.listToAttrs (
            map (
              h:
              lib.nameValuePair h.name (mkSystem {
                host = h.name;
                inherit (h) system;
                inherit extraSpecialArgs extraModules extraNixosModules;
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
            lib.listToAttrs (
              lib.concatMap (
                p:
                if p.system == null || p.system == sys then
                  [ (lib.nameValuePair p.name (callPackage nixpkgs.legacyPackages.${sys} p.path)) ]
                else
                  [ ]
              ) packageDefs
            )
          );

          devShells = forAllSystems systems (
            sys:
            lib.listToAttrs (
              map (
                s: lib.nameValuePair s.name (callPackage nixpkgs.legacyPackages.${sys} s.path)
              ) discovered.shells
            )
          );

          checks = forAllSystems systems (
            sys:
            lib.listToAttrs (
              map (
                s: lib.nameValuePair s.name (callPackage nixpkgs.legacyPackages.${sys} s.path)
              ) discovered.checks
            )
          );

          overlays = lib.listToAttrs (
            map (
              o: lib.nameValuePair o.name ((import o.path) { inherit inputs self cloud; })
            ) discovered.overlays
          );

          userLib = lib.listToAttrs (
            map (
              f: lib.nameValuePair (lib.removeSuffix ".nix" f.name) (importFile (root + "/lib/" + f.name))
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
                      inherit extraSpecialArgs extraModules extraHomeModules;
                    })
                  )
                  (lib.filter (h: builtins.pathExists (root + "/homes/" + h.user + "/default.nix")) discovered.homes)
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
                          ;
                      })
                    )
                    (
                      lib.filter (
                        host:
                        builtins.pathExists (root + "/homes/" + h.user + "/" + host + ".nix")
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
            nixosModules = lib.listToAttrs (
              map (p: lib.nameValuePair (moduleKey p) p) discovered.autoModules.nixos
            );
            homeModules = lib.listToAttrs (
              map (p: lib.nameValuePair (moduleKey p) p) discovered.autoModules.home
            );
          };
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
      inherit sops';
    };

  mkLib = { inputs }: bind { inherit inputs; };

  mkFlake =
    args@{ inputs, ... }:
    (bind {
      inherit inputs;
      moduleRegistries = args.moduleRegistries or [ ];
    }).mkFlake
      (
        builtins.removeAttrs args [
          "inputs"
          "moduleRegistries"
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
