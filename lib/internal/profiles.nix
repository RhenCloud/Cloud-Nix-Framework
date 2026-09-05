# profiles.nix — profile 定义的解析与校验（纯函数，可单测）
#
# profile 与 moduleGroups 的区别：
#   - moduleGroups 是模块侧声明的 all-of 硬依赖，不会自动启用成员；
#   - profiles 是主机侧声明的启用包，成员会被启用（仍走 override 与冲突校验）。
#
# 定义形状与 moduleGroups 一致：
#   - 字符串列表：成员在 NixOS 与 home 两侧同时生效
#   - { extends; common; nixos; home; }：可继承其他 profile，并分侧声明成员
{ lib }:

let
  readStringList =
    {
      field,
      source,
      value,
    }:
    if builtins.isList value && lib.all (item: builtins.isString item && item != "") value then
      lib.unique value
    else
      throw ''
        invalid profile definition

        '${field}' in ${source} must be a list of non-empty strings
        current type: ${builtins.typeOf value}
      '';

  readProfile =
    {
      name,
      value,
      source,
    }:
    if name == "" then
      throw "profile name must be a non-empty string"
    else if builtins.isList value then
      let
        members = readStringList {
          field = name;
          inherit source value;
        };
      in
      if members == [ ] then
        throw "profile '${name}' (${source}) must not be empty"
      else
        {
          extends = [ ];
          nixos = members;
          home = members;
        }
    else if builtins.isAttrs value then
      let
        supportedFieldsSet = {
          extends = true;
          common = true;
          nixos = true;
          home = true;
        };
        unknownFields = lib.filter (field: !builtins.hasAttr field supportedFieldsSet) (
          builtins.attrNames value
        );
        common = readStringList {
          field = "${name}.common";
          inherit source;
          value = value.common or [ ];
        };
        nixos = readStringList {
          field = "${name}.nixos";
          inherit source;
          value = value.nixos or [ ];
        };
        home = readStringList {
          field = "${name}.home";
          inherit source;
          value = value.home or [ ];
        };
        extends = readStringList {
          field = "${name}.extends";
          inherit source;
          value = value.extends or [ ];
        };
      in
      if unknownFields != [ ] then
        throw "profile '${name}' (${source}) contains unsupported fields: ${lib.concatStringsSep ", " unknownFields}"
      else if extends ++ common ++ nixos ++ home == [ ] then
        throw "profile '${name}' (${source}) must not be empty"
      else
        {
          inherit extends;
          nixos = lib.unique (common ++ nixos);
          home = lib.unique (common ++ home);
        }
    else
      throw ''
        invalid profile definition

        profile '${name}' (${source}) must be either a list of strings or an attrset with extends/common/nixos/home fields
      '';

  resolveProfiles =
    definitions:
    let
      names = builtins.attrNames definitions;
      knownSet = lib.genAttrs names (_: true);
      resolve =
        trail: name:
        let
          definition = definitions.${name};
          cycle = trail ++ [ name ];
          unknown = lib.filter (parent: !builtins.hasAttr parent knownSet) definition.extends;
          inherited = map (resolve cycle) definition.extends;
        in
        if builtins.elem name trail then
          throw "profile inheritance cycle: ${lib.concatStringsSep " -> " cycle}"
        else if unknown != [ ] then
          throw "profile '${name}' (${definition.source}) extends unknown profile(s): ${lib.concatStringsSep ", " unknown}"
        else
          {
            inherit (definition) source extends;
            nixos = lib.unique (lib.concatMap (profile: profile.nixos) inherited ++ definition.nixos);
            home = lib.unique (lib.concatMap (profile: profile.home) inherited ++ definition.home);
          };
    in
    lib.genAttrs names (resolve [ ]);

  checkMembers =
    {
      profile,
      source,
      side,
      members,
      knownNames,
    }:
    let
      knownSet = lib.genAttrs knownNames (_: true);
      unknown = lib.filter (member: !builtins.hasAttr member knownSet) members;
    in
    if unknown == [ ] then
      members
    else
      throw ''
        profile references unknown module(s) (${side} side)

        profile '${profile}' (${source}) references: ${lib.concatStringsSep ", " unknown}

        hint: module names are derived from directory paths (e.g. desktop.hyprland).
        For side-specific modules, use the split form { nixos = [...]; home = [...]; }
      '';

  checkHostProfiles =
    {
      host,
      declared,
      knownProfiles,
    }:
    let
      unknown = lib.filter (profile: !builtins.hasAttr profile knownProfiles) declared;
    in
    if unknown == [ ] then
      declared
    else
      let
        available = builtins.attrNames knownProfiles;
      in
      throw ''
        host '${host}' declares unknown profile(s)

        unknown profiles: ${lib.concatStringsSep ", " unknown}
        ${
          if available == [ ] then
            "no profiles are defined in this project (create profiles/<name>.nix or pass mkFlake.profiles)"
          else
            "available profiles: ${lib.concatStringsSep ", " available}"
        }
      '';
in
{
  inherit
    readProfile
    resolveProfiles
    checkMembers
    checkHostProfiles
    ;
}
