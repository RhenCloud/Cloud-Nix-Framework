# 模块依赖系统

从 0.5.0 起，模块目录可通过纯数据 `meta.nix` 声明模块之间的硬依赖、排序、弱依赖和冲突。框架在发现阶段建立 NixOS 与 home-manager 两张独立的依赖图，在组合阶段按主机解析最终模块集合。

## 基础用法

```nix
# modules/desktop/hyprland/meta.nix
{
  requires = [ "desktop.base" ];
  after = [ "desktop.fonts" ];
  before = [ "desktop.portal" ];
  wants = [ "desktop.gaming" ];
  conflicts = [ "desktop.gnome" ];
}
```

模块名由目录路径推导：

```text
modules/desktop/hyprland/ → desktop.hyprland
modules/_common/base/     → _common.base
```

引用必须使用完整点分模块名，不支持文件路径和通配符。

## 字段语义

### `requires`

硬依赖。当前模块启用时，目标模块必须在同一侧启用：

```nix
{
  requires = [ "desktop.base" ];
}
```

`requires` 同时保证目标模块排在当前模块之前。若目标被角色过滤或被主机覆盖禁用，组合立即失败并显示依赖方、缺失目标和禁用原因。

### `after` 与 `before`

软顺序约束。仅当两个模块都启用时生效，对方未启用不会报错：

```nix
{
  after = [ "desktop.fonts" ];
  before = [ "desktop.portal" ];
}
```

### `wants`

弱依赖。目标启用时，当前模块排在目标之后；目标未启用时忽略：

```nix
{
  wants = [ "desktop.gaming" ];
}
```

它与 `after` 的排序效果相同，但表达的是「可选能力」而不是单纯顺序。

### `conflicts`

互斥关系。两个模块在同一主机、同一侧同时启用时组合失败：

```nix
{
  conflicts = [ "desktop.gnome" ];
}
```

冲突按无向关系处理，只需由任意一侧声明。

## 分侧控制

同一模块目录可能同时包含 NixOS 与 home-manager 文件，可用分侧开关排除其中一侧：

```nix
{
  nixos.enable = true;
  home.enable = false;
}
```

依赖关系始终在同侧解析。NixOS 模块不能通过 `requires` 依赖仅存在于 home-manager 侧的模块，反之亦然。

## 与角色和主机覆盖的关系

组合顺序如下：

1. 根据主机 `roles` 过滤自动发现模块；
2. 应用 `hosts/<host>/meta.nix` 中的 `modules` 覆盖；
3. 校验 `requires` 闭包与 `conflicts`；
4. 执行稳定拓扑排序；
5. 追加外部注册表模块、主机或用户模块以及显式传入的额外模块。

显式设置为 `true` 会启用被角色过滤的本地模块：

```nix
# hosts/workstation/meta.nix
{
  system = "x86_64-linux";
  roles = [ "desktop" ];

  modules = {
    "development.rust" = true;
    "desktop.gaming" = false;
  };
}
```

若 `desktop.hyprland` 硬依赖 `desktop.base`，则不能只禁用 `desktop.base` 而保留依赖方。框架会在 NixOS 或 home-manager 配置进入深层求值前报告错误。

## 确定性与循环检测

框架使用稳定拓扑排序。没有依赖边时，结果与原来的模块名字典序一致；多个节点同时可选时，也始终选择名字典序最小的节点。

以下错误在发现阶段直接报告：

- 引用未知模块；
- 模块引用自身；
- 依赖环；
- 同一模块同时 `requires` 和 `conflicts` 另一个模块；
- 字段类型错误。

## 查看依赖图

`checks.<system>.cloud-discovery` 报告包含全局图与各主机解析结果：

```bash
nix build .#checks.x86_64-linux.cloud-discovery
jq '.moduleGraph, .perHost' result
```

关键字段：

- `moduleGraph.<side>.nodes`：该侧节点；
- `moduleGraph.<side>.edges`：依赖和顺序边；
- `moduleGraph.<side>.order`：全局稳定拓扑序；
- `perHost.<host>.<side>.enabled`：主机最终启用模块；
- `perHost.<host>.<side>.disabledReasons`：未启用原因。
