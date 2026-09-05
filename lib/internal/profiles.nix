# profiles.nix — profile 定义的解析与校验（纯函数，可单测）
#
# profile 与 moduleGroups 的区别：
#   - moduleGroups 是模块侧声明的 all-of 硬依赖，不会自动启用成员；
#   - profiles 是主机侧声明的启用包，成员会被启用（仍走 override 与冲突校验）。
#
# 定义形状与 moduleGroups 一致：
#   - 字符串列表：成员在 NixOS 与 home 两侧同时生效
#   - { common; nixos; home; }：分侧声明，nixos = common ++ nixos，home = common ++ home
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
        error: profile 定义无效

        ${source} 中的 '${field}' 必须是非空字符串组成的列表
        当前类型：${builtins.typeOf value}
      '';

  readProfile =
    {
      name,
      value,
      source,
    }:
    if name == "" then
      throw "profile 的名称必须是非空字符串"
    else if builtins.isList value then
      let
        members = readStringList {
          field = name;
          inherit source value;
        };
      in
      if members == [ ] then
        throw "profile '${name}'（${source}）不能为空"
      else
        {
          nixos = members;
          home = members;
        }
    else if builtins.isAttrs value then
      let
        supportedFieldsSet = {
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
      in
      if unknownFields != [ ] then
        throw "profile '${name}'（${source}）包含不支持的字段：${lib.concatStringsSep ", " unknownFields}"
      else if common ++ nixos ++ home == [ ] then
        throw "profile '${name}'（${source}）不能为空"
      else
        {
          nixos = lib.unique (common ++ nixos);
          home = lib.unique (common ++ home);
        }
    else
      throw ''
        error: profile 定义无效

        profile '${name}'（${source}）必须是字符串列表或包含 common/nixos/home 的属性集
      '';

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
        error: profile 引用了未知模块（${side} 侧）

        profile '${profile}'（${source}）引用了：${lib.concatStringsSep ", " unknown}

        提示：模块名由目录路径推导（如 desktop.hyprland）；仅某侧存在的模块
        请使用分侧写法 { nixos = [...]; home = [...]; }
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
        error: 主机 '${host}' 声明了未知 profile

        未知 profile：${lib.concatStringsSep ", " unknown}
        ${
          if available == [ ] then
            "当前项目没有定义任何 profile（可创建 profiles/<name>.nix 或传入 mkFlake.profiles）"
          else
            "可用 profile：${lib.concatStringsSep ", " available}"
        }
      '';
in
{
  inherit
    readProfile
    checkMembers
    checkHostProfiles
    ;
}
