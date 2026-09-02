# 模块依赖系统

从 0.5.0 起，模块目录可通过纯数据 `meta.nix` 声明依赖、顺序、模块组和虚拟能力。框架为 NixOS 与 home-manager 分别建立依赖图，并按主机解析最终模块集合。

## 基础字段

```nix
{
  requires = [ "desktop.base" ];
  after = [ "desktop.fonts" ];
  before = [ "desktop.portal" ];
  wants = [ "desktop.gaming" ];
  conflicts = [ "desktop.gnome" ];
}
```

- `requires`：同侧硬依赖，同时保证依赖目标先加载。
- `after` / `before`：双方启用时生效的软顺序约束。
- `wants`：目标启用时排在目标之后，未启用不报错。
- `conflicts`：双方同时启用时组合失败。

模块名由目录路径推导，例如 `modules/desktop/hyprland/` 对应 `desktop.hyprland`。引用不支持路径或通配符。

## 分侧依赖

所有关系字段均可在 `nixos` 和 `home` 下追加：

```nix
{
  requires = [ "common.base" ];

  nixos = {
    enable = true;
    requires = [ "nixos.base" ];
    after = [ "nixos.services" ];
  };

  home = {
    enable = true;
    requires = [ "home.base" ];
    conflicts = [ "home.minimal" ];
  };
}
```

有效值为“顶层共享字段 + 当前侧字段”。NixOS-only 引用不会污染 home-manager 图。

## 模块组

组在 `mkFlake` 顶层集中注册：

```nix
moduleGroups = {
  desktop-stack = [
    "desktop.audio"
    "desktop.portal"
  ];

  workstation = {
    common = [ "desktop.fonts" ];
    nixos = [ "desktop.display" ];
    home = [ "desktop.theme" ];
  };
};
```

模块通过 `requiresGroups` 使用组：

```nix
{
  requiresGroups = [ "desktop-stack" ];
}
```

组是 all-of 硬依赖。列表形式两侧共享；属性集形式使用 `common + 当前侧`。组不会自动启用成员，成员仍需被角色或主机 override 选中。

## 虚拟能力

```nix
# provider
{
  provides = [ "display-server" ];
}

# consumer
{
  requiresCapabilities = [ "display-server" ];
}
```

能力是 any-of：当前已启用集合中至少存在一个 provider 即满足。框架不会自动选择或启用 provider；多个 provider 同时启用时都排在 consumer 前。三个字段也支持顶层共享与 `nixos`/`home` 分侧追加。

## 与角色和主机覆盖的关系

组合顺序：

1. 根据主机 `roles` 过滤模块；
2. 应用主机 `modules` override；
3. 展开模块组，校验硬依赖、能力和冲突；
4. 对最终子图执行稳定拓扑排序；
5. 追加注册表、主机、用户和显式额外模块。

组和能力不会绕过角色过滤，也不会自动启用模块。

## 图与诊断

```bash
nix build .#checks.x86_64-linux.snowveil-discovery
jq '.moduleGraph, .perHost' result

nix build .#checks.x86_64-linux.snowveil-module-graph-dot
find result -name '*.dot' -print
```

JSON 包含节点详情、组、能力 provider、边、全局顺序，以及逐主机的启用、禁用和能力满足原因。DOT derivation 输出全局 NixOS/HM 图和逐主机图，内容按字典序稳定生成。

未知模块或组、自引用、缺失硬依赖、缺失能力、冲突和循环都会以对应侧和目标为单位报告。
