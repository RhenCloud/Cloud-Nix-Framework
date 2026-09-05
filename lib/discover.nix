# discover.nix — 目录自动发现
#
# 主机目录约定：
#   hosts/<name>/                 meta.nix 必须声明 system = "..."
#
# 主机目录内固定分拣 magic 文件（存在则按此顺序 import，允许缺失）：
#   default.nix（必需）→ hardware.nix → disk.nix → network.nix
# meta.nix 只作为元数据读取；其余 .nix 文件不会自动导入（输出 trace 警告）。
{
  lib,
  fs,
  projectRoot,
  moduleRegistries,
  moduleGroups ? { },
  profiles ? { },
}:

let
  depGraph = import ./internal/depgraph.nix { inherit lib; };
  profileTools = import ./internal/profiles.nix { inherit lib; };

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
      else if value == null then
        { }
      else
        throw "metadata file '${toString path}' must directly return an attribute set";

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

  hostFragmentFiles = [
    "hardware.nix"
    "disk.nix"
    "network.nix"
  ];

  parseHostDir =
    e:
    let
      rawName = e.name;
      relDir = "hosts/" + rawName;
      metaPath = projectRoot + "/${relDir}/meta.nix";
      defPath = projectRoot + "/${relDir}/default.nix";
      meta = readMetadata metaPath;
      fragmentPaths = lib.filter builtins.pathExists (
        map (name: projectRoot + "/${relDir}/${name}") hostFragmentFiles
      );
      knownFiles = lib.genAttrs (
        [
          "meta.nix"
          "default.nix"
        ]
        ++ hostFragmentFiles
      ) (_: true);
      strayFiles = map (f: f.name) (
        lib.filter (f: !builtins.hasAttr f.name knownFiles) (nixFiles (listDirAt relDir))
      );
      withStrayWarning =
        if strayFiles == [ ] then
          lib.id
        else
          builtins.trace "warning: files ${lib.concatStringsSep ", " strayFiles} under hosts/${rawName}/ are not host magic files and will not be auto-imported; import them explicitly from the host module if needed";
    in
    if !builtins.pathExists defPath then
      null
    else
      withStrayWarning {
        dir = rawName;
        name = rawName;
        path = defPath;
        modulePaths = [ defPath ] ++ fragmentPaths;
        inherit metaPath;
        inherit meta;
        system =
          let
            sys = meta.system or null;
          in
          if sys == null then
            builtins.throw "hosts/${rawName}/meta.nix must declare system (e.g. system = \"x86_64-linux\")"
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

  fileProfiles = builtins.listToAttrs (
    map (
      file:
      lib.nameValuePair (lib.removeSuffix ".nix" file.name) {
        source = "profiles/${file.name}";
        value = import (projectRoot + "/profiles/" + file.name);
      }
    ) (nixFiles (listDirAt "profiles"))
  );

  duplicateProfiles = lib.intersectLists (builtins.attrNames fileProfiles) (
    builtins.attrNames profiles
  );

  allProfileDefs =
    if duplicateProfiles != [ ] then
      throw "profile name conflict: ${lib.concatStringsSep ", " duplicateProfiles} defined both in profiles/ and mkFlake.profiles; keep only one"
    else
      fileProfiles
      // lib.mapAttrs (name: value: {
        source = "mkFlake.profiles.${name}";
        inherit value;
      }) profiles;

  profiles' = lib.mapAttrs (
    name: def:
    let
      normalized = profileTools.readProfile {
        inherit name;
        inherit (def) source value;
      };
    in
    {
      inherit (def) source;
      nixos = profileTools.checkMembers {
        profile = name;
        inherit (def) source;
        side = "nixos";
        members = normalized.nixos;
        knownNames = builtins.attrNames moduleGraph.nixos.nodes;
      };
      home = profileTools.checkMembers {
        profile = name;
        inherit (def) source;
        side = "home";
        members = normalized.home;
        knownNames = builtins.attrNames moduleGraph.home.nodes;
      };
    }
  ) allProfileDefs;

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

  normalizeHosts =
    user: hosts:
    if hosts == null then
      throw "users/${user}/meta.nix must declare hosts (e.g. hosts = [ \"nixos-desktop\" ])"
    else if !builtins.isList hosts then
      throw "users/${user}/meta.nix hosts must be a list of strings"
    else if !lib.all (host: builtins.isString host) hosts then
      throw "users/${user}/meta.nix hosts must be a list of strings"
    else
      hosts;

  parseUserDir =
    e:
    let
      rawName = e.name;
      metaPath = projectRoot + "/users/" + rawName + "/meta.nix";
      defPath = projectRoot + "/users/" + rawName + "/default.nix";
      meta = readMetadata metaPath;
    in
    if !builtins.pathExists metaPath then
      null
    else
      {
        name = rawName;
        inherit metaPath meta;
        defaultPath = if builtins.pathExists defPath then defPath else null;
        hosts = normalizeHosts rawName (meta.hosts or null);
      };

  users = lib.filter (user: user != null) (map parseUserDir (onlyDirs (listDirAt "users")));
  usersByName = builtins.listToAttrs (map (user: lib.nameValuePair user.name user) users);
  usersByHost = lib.mapAttrs (_: us: map (user: user.name) us) (
    lib.groupBy (entry: entry.host) (
      lib.concatMap (
        user:
        map (host: {
          inherit host;
          inherit (user) name;
        }) user.hosts
      ) users
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
    users
    usersByName
    usersByHost
    ;

  profiles = profiles';

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
