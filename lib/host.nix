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

  resolveHost =
    host:
    let
      matches = lib.filter (h: h.name == host) discovered.hosts;
    in
    if matches == [ ] then
      throw "未发现主机 '${host}'，请在 hosts/${host}.<system>/ 下创建 default.nix"
    else
      lib.head matches;

  hostMetadataFor =
    { host, pkgs }:
    let
      hostRec = resolveHost host;
      hasMeta = builtins.pathExists hostRec.metaPath;
    in
    if hasMeta then
      normalizeHostMetadata hostRec.meta
    else
      let
        hostArgs = {
          inherit lib pkgs;
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
