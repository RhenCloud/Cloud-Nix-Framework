# 模块过滤和覆盖逻辑
{ lib }:

let
  # 将路径转换为模块名称
  # modules/desktop/gaming/nixos.nix → "desktop.gaming"
  # modules/_common/base/default.nix → "_common.base"
  pathToModuleName =
    path:
    let
      # 将 /path/to/modules/desktop/gaming/nixos.nix 转换为 desktop/gaming
      asStr = builtins.toString path;
      # 查找 /modules/ 后面的部分
      parts = lib.splitString "/modules/" asStr;
    in
    if lib.length parts >= 2 then
      let
        afterModules = lib.last parts;
        # 移除最后的文件名（nixos.nix, home.nix, default.nix）
        dir = builtins.dirOf afterModules;
        # 用点替换斜杠
        moduleName = lib.replaceStrings [ "/" ] [ "." ] dir;
      in
      if moduleName == "" || moduleName == "." then null else moduleName
    else
      null;

  # 应用 meta.nix 中的模块覆盖
  # overrides: { "desktop.gaming" = false; "development.rust" = true; }
  # modules: 发现的模块路径列表
  applyModuleOverrides =
    { overrides, modules }:
    let
      # 构建模块名称 → 启用状态的映射
      overrideMap = overrides;

      isModuleEnabled =
        modulePath:
        let
          moduleName = pathToModuleName modulePath;
        in
        if moduleName == null then
          true
        else
          let
            override = overrideMap.${moduleName} or null;
          in
          if override == null then true else override;
    in
    lib.filter isModuleEnabled modules;

  # 验证 modules 覆盖结构
  validateModuleOverrides =
    overrides:
    if !builtins.isAttrs overrides then
      throw "meta.nix 中的 modules 必须是属性集，当前类型为 ${builtins.typeOf overrides}"
    else
      lib.mapAttrs (
        name: value:
        if builtins.isBool value || value == null then
          value
        else
          throw "modules.${name} 的值必须是布尔值或 null，当前为 ${builtins.typeOf value}"
      ) overrides;
in

{
  inherit pathToModuleName applyModuleOverrides validateModuleOverrides;
}
