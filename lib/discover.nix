# discover.nix — 目录自动发现
#
# 主机目录支持两种约定：
#   hosts/<name>.<system>/          后缀必须是 lib.systems.flakeExposed 中的已知 system
#   hosts/<name>/                   无后缀，但 meta.nix 须声明 system = "..."
#
# 两种写法可共存；不满足任一条件的目录输出 trace 警告并跳过，不会 throw。
{
  lib,
  fs,
  projectRoot,
  moduleRegistries,
  moduleGroups ? { },
}:

let
  depGraph = import ./internal/depgraph.nix { inherit lib; };

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

  parseHostDir =
    e:
    let
      rawName = e.name;
      metaPath = projectRoot + "/hosts/" + rawName + "/meta.nix";
      defPath = projectRoot + "/hosts/" + rawName + "/default.nix";
      meta = readMetadata metaPath;
    in
    if !builtins.pathExists defPath then
      null
    else
      {
        dir = rawName;
        name = rawName;
        path = defPath;
        inherit metaPath;
        inherit meta;
        system =
          let
            sys = meta.system or null;
          in
          if sys == null then
            builtins.throw "Snowveil 框架错误：hosts/${rawName}/meta.nix 必须声明 system（例如 system = \"x86_64-linux\"）"
          else
            sys;
      };

  localGroupedModules =
    if builtins.pathExists (projectRoot + "/modules") then
      fs.groupModules (projectRoot + "/modules")
    else
      {
        nixos = { };
        home = { };
        meta = { };
        index = { };
      };

  moduleGraph = {
    nixos = depGraph.buildGraph {
      grouped = localGroupedModules;
      side = "nixos";
      inherit moduleGroups;
    };
    home = depGraph.buildGraph {
      grouped = localGroupedModules;
      side = "home";
      inherit moduleGroups;
    };
  };

  localAutoModules = {
    nixos = lib.concatMap (name: localGroupedModules.nixos.${name}) moduleGraph.nixos.order;
    home = lib.concatMap (name: localGroupedModules.home.${name}) moduleGraph.home.order;
  };

  registryModules =
    lib.foldl'
      (acc: registry: {
        nixos = acc.nixos ++ registry.modules.nixos or [ ];
        home = acc.home ++ registry.modules.home or [ ];
      })
      {
        nixos = [ ];
        home = [ ];
      }
      moduleRegistries;

  rawPackageDirs = onlyDirs (listDirAt "packages");

  directPackages =
    map
      (d: {
        inherit (d) name;
        path = projectRoot + "/packages/" + d.name + "/default.nix";
        meta = readMetadata (projectRoot + "/packages/" + d.name + "/meta.nix");
        explicitSystem = null;
      })
      (
        lib.filter (
          d: builtins.pathExists (projectRoot + "/packages/" + d.name + "/default.nix")
        ) rawPackageDirs
      );

  systemFirstPackages = lib.concatMap (
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
  ) rawPackageDirs;

  hosts = lib.filter (host: host != null) (map parseHostDir (onlyDirs (listDirAt "hosts")));
  hostsByName = builtins.listToAttrs (map (host: lib.nameValuePair host.name host) hosts);

  homes = map (
    directory:
    let
      files = nixFiles (listDirAt ("homes/" + directory.name));
      defaultPath =
        let
          path = projectRoot + "/homes/" + directory.name + "/default.nix";
        in
        if builtins.pathExists path then path else null;
      hostFiles = lib.filter (file: file.name != "default.nix") files;
      hostModules = builtins.listToAttrs (
        map (
          file:
          lib.nameValuePair (lib.removeSuffix ".nix" file.name) (
            projectRoot + "/homes/" + directory.name + "/" + file.name
          )
        ) hostFiles
      );
    in
    {
      user = directory.name;
      inherit defaultPath hostModules;
      hosts = builtins.attrNames hostModules;
    }
  ) (onlyDirs (listDirAt "homes"));
  homesByUser = builtins.listToAttrs (map (home: lib.nameValuePair home.user home) homes);
  usersByHost = lib.mapAttrs (_: records: map (record: record.user) records) (
    lib.groupBy (record: record.host) (
      lib.concatMap (
        home:
        map (host: {
          inherit host;
          inherit (home) user;
        }) home.hosts
      ) homes
    )
  );

in
{
  inherit
    localGroupedModules
    localAutoModules
    moduleGraph
    registryModules
    readMetadata
    nixFiles
    listDirAt
    onlyDirs
    hosts
    hostsByName
    homes
    homesByUser
    usersByHost
    ;

  packages = directPackages ++ systemFirstPackages;

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
  shells = namedOutputsAt "shells";
  checks = namedOutputsAt "checks";

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

  libFiles = nixFiles (listDirAt "lib");
}
