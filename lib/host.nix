# host.nix — host 元数据读取、角色解析、per-host HM 策略
{
  lib,
  discovered,
}:

let
  normalizeRoles =
    roles:
    if roles == null then
      null
    else if builtins.isString roles then
      [ roles ]
    else if builtins.isList roles && lib.all builtins.isString roles then
      roles
    else
      throw "host role/roles must be a string or list of strings, got ${builtins.typeOf roles}";

  normalizeProfiles =
    profiles:
    if profiles == null then
      [ ]
    else if builtins.isString profiles then
      [ profiles ]
    else if builtins.isList profiles && lib.all builtins.isString profiles then
      profiles
    else
      throw "host profiles must be a string or list of strings, got ${builtins.typeOf profiles}";

  # 读取一个 bool? 字段，支持新旧两种路径
  # newPath: 新推荐路径（如 raw.home.embed）
  # oldPaths: 旧路径列表 { value; name; } 带 deprecated 警告
  readBoolField =
    {
      newValue,
      oldPaths,
    }:
    if newValue != null then
      newValue
    else
      lib.foldl' (
        acc: old:
        if acc != null then
          acc
        else if old.value != null then
          builtins.trace "warning: meta.nix field '${old.name}' is deprecated, migrate to '${old.newName}'" old.value
        else
          null
      ) null oldPaths;

  normalizeHostMetadata =
    raw:
    let
      homeMeta = raw.home or { };
      # 旧式扁平字段
      oldEmbed = raw.embedHomeManager or null;
      oldUseGlobalPkgs = raw.homeManagerUseGlobalPkgs or null;
      # 旧式 homeManager.* 嵌套字段
      oldHmMeta = raw.homeManager or { };
      oldHmEmbed = oldHmMeta.embed or null;
      oldHmUseGlobalPkgs = oldHmMeta.useGlobalPkgs or null;
    in
    {
      roles = normalizeRoles (raw.roles or raw.role or null);
      profiles = normalizeProfiles (raw.profiles or null);
      modules = raw.modules or { };
      embedHomeManager = readBoolField {
        newValue = homeMeta.embed or null;
        oldPaths = [
          {
            value = oldEmbed;
            name = "embedHomeManager";
            newName = "home.embed";
          }
          {
            value = oldHmEmbed;
            name = "homeManager.embed";
            newName = "home.embed";
          }
        ];
      };
      homeManagerUseGlobalPkgs = readBoolField {
        newValue = homeMeta.useGlobalPkgs or null;
        oldPaths = [
          {
            value = oldUseGlobalPkgs;
            name = "homeManagerUseGlobalPkgs";
            newName = "home.useGlobalPkgs";
          }
          {
            value = oldHmUseGlobalPkgs;
            name = "homeManager.useGlobalPkgs";
            newName = "home.useGlobalPkgs";
          }
        ];
      };
    };

  resolveHost =
    host:
    discovered.hostsByName.${host}
      or (throw "host '${host}' was not discovered; create hosts/${host}/ and declare system in meta.nix");

  hostMetadataFor =
    { host, ... }:
    normalizeHostMetadata (resolveHost host).meta;

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
          throw "${name} must be a boolean, a host -> bool function, or a per-host attrset";
    in
    if builtins.isBool resolved then
      resolved
    else
      throw "${name} resolved to a non-boolean value for host '${host}'";

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
      throw "metadata field ${key} for host '${host}' must be a boolean";

  rolesFor =
    { host, ... }:
    (hostMetadataFor { inherit host; }).roles;

in
{
  inherit
    normalizeRoles
    normalizeProfiles
    normalizeHostMetadata
    resolveHost
    hostMetadataFor
    resolveHostPolicy
    hostPolicyFromMetadata
    rolesFor
    ;
}
