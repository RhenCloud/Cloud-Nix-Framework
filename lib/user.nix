# user.nix — 用户元数据归一化与系统用户/组生成
#
# users/<name>/meta.nix 声明用户属性（uid、组、extraGroups、hashedPasswordSecret 等）。
# 组合层据此自动生成 users.users.<name> 与 users.groups.<name>，默认值用 mkDefault 包裹，
# 可由 users/<name>/default.nix 或主机模块覆盖。
#
# hashedPasswordSecret 约定：
#   - 以 "/" 开头 → 视为字面文件路径，直接作为 hashedPasswordFile；
#   - 否则 → sops 密钥名，hashedPasswordFile 指向 config.sops.secrets.<name>.path。
{
  lib,
}:

let
  normalizeUserMetadata =
    {
      name,
      meta,
    }:
    let
      secret = meta.hashedPasswordSecret or null;
      isLiteralPath = secret != null && lib.hasPrefix "/" (toString secret);
      uid = meta.uid or null;
    in
    {
      inherit name;
      inherit uid;
      gid = meta.gid or uid;
      group = meta.group or name;
      extraGroups = meta.extraGroups or [ ];
      description = meta.description or null;
      home = meta.home or null;
      createHome = meta.createHome or true;
      isNormalUser = meta.isNormalUser or true;
      hashedPasswordFile = if isLiteralPath then secret else null;
      hashedPasswordSecretName = if secret != null && !isLiteralPath then secret else null;
    };

  mkSystemUser =
    n:
    {
      isNormalUser = lib.mkDefault n.isNormalUser;
      createHome = lib.mkDefault n.createHome;
      inherit (n) group;
      extraGroups = lib.mkDefault n.extraGroups;
    }
    // lib.optionalAttrs (n.home != null) { inherit (n) home; }
    // lib.optionalAttrs (n.uid != null) { uid = lib.mkDefault n.uid; }
    // lib.optionalAttrs (n.description != null) { description = lib.mkDefault n.description; }
    // lib.optionalAttrs (n.hashedPasswordFile != null) {
      hashedPasswordFile = lib.mkDefault n.hashedPasswordFile;
    };

  mkSystemGroup = gid: { } // lib.optionalAttrs (gid != null) { gid = lib.mkDefault gid; };

  mkUsersModule =
    {
      users,
      sopsFile,
    }:
    { config, lib, ... }:
    let
      entries = map (u: {
        inherit (u) name;
        n = normalizeUserMetadata {
          inherit (u) name;
          inherit (u) meta;
        };
      }) users;
      byName = builtins.listToAttrs (map (e: lib.nameValuePair e.name e) entries);
      sopsUsers = lib.filter (e: e.n.hashedPasswordSecretName != null) entries;
      sopsSecrets = builtins.listToAttrs (
        map (e: lib.nameValuePair e.n.hashedPasswordSecretName { inherit sopsFile; }) sopsUsers
      );
    in
    {
      users.users = lib.mapAttrs (
        _: e:
        mkSystemUser e.n
        // lib.optionalAttrs (e.n.hashedPasswordSecretName != null) {
          hashedPasswordFile = lib.mkDefault config.sops.secrets.${e.n.hashedPasswordSecretName}.path;
        }
      ) byName;

      users.groups = builtins.listToAttrs (
        map (e: lib.nameValuePair e.n.group (mkSystemGroup e.n.gid)) entries
      );
    }
    // lib.optionalAttrs (sopsSecrets != { }) {
      sops.secrets = sopsSecrets;
    };
in
{
  inherit
    normalizeUserMetadata
    mkSystemUser
    mkSystemGroup
    mkUsersModule
    ;
}
