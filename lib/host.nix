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
      throw "主机 role/roles 必须是字符串或字符串列表，当前类型为 ${builtins.typeOf roles}";

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
          builtins.trace "警告：meta.nix 字段 '${old.name}' 已弃用，请迁移到 '${old.newName}'" old.value
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
    let
      matches = lib.filter (h: h.name == host) discovered.hosts;
    in
    if matches == [ ] then
      throw "未发现主机 '${host}'，请创建 hosts/${host}/ 目录并在 meta.nix 中声明 system"
    else
      lib.head matches;

  hostMetadataFor =
    { host, pkgs }:
    let
      hostRec = resolveHost host;
    in
    normalizeHostMetadata hostRec.meta;

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
    { host, pkgs }:
    (hostMetadataFor { inherit host pkgs; }).roles;

in
{
  inherit
    normalizeRoles
    normalizeHostMetadata
    resolveHost
    hostMetadataFor
    resolveHostPolicy
    hostPolicyFromMetadata
    rolesFor
    ;
}
