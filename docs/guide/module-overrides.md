# 细粒度模块控制

从 0.4.0 起，Cloud Nix Framework 支持在主机级别覆盖模块的启用/禁用状态，提供比角色系统更细粒度的控制。

## 问题场景

假设有以下模块结构：

```
modules/
├── desktop/
│   ├── nixos.nix           # desktop 基础配置
│   ├── hyprland/           # Wayland 桌面
│   │   └── nixos.nix
│   └── gaming/             # 游戏相关
│       └── nixos.nix
└── development/
    └── rust/
        └── nixos.nix
```

主机配置：

```nix
# hosts/workstation/meta.nix
{
  system = "x86_64-linux";
  roles = [ "desktop" "development" ];  # 自动加载 desktop/* 和 development/*
}
```

现在的问题是：**无法禁用 desktop 中的某个特定模块**（如 gaming），因为角色系统是"全或无"的。

## 解决方案

### 基础：按模块路径禁用

在主机的 `meta.nix` 中声明模块覆盖：

```nix
# hosts/workstation/meta.nix
{
  system = "x86_64-linux";
  roles = [ "desktop" "development" ];

  # 新增：模块级别的控制
  modules = {
    "desktop.gaming" = false;            # 禁用游戏模块
    "desktop.hyprland" = true;           # 显式启用（可选）
  };
}
```

模块名称遵循目录结构：

```
modules/desktop/gaming/nixos.nix  →  "desktop.gaming"
modules/desktop/hyprland/nixos.nix → "desktop.hyprland"
modules/development/rust/nixos.nix → "development.rust"
modules/_common/base.nix           → "_common.base"
```

### 场景 1：禁用某个游戏模块

```nix
# hosts/server/meta.nix
{
  system = "x86_64-linux";
  roles = [ "server" ];
  
  # 虽然加载了 server 角色的模块，但禁用了游戏支持
  modules = {
    "gaming.nvidia" = false;
  };
}
```

### 场景 2：跨角色启用模块

```nix
# hosts/special-box/meta.nix
{
  system = "x86_64-linux";
  roles = [ "minimal" ];
  
  # 强制启用通常不属于此角色的模块
  modules = {
    "development.debugging" = true;
    "server.monitoring" = true;
  };
}
```

### 场景 3：混合控制

```nix
# hosts/dev-workstation/meta.nix
{
  system = "x86_64-linux";
  roles = [ "desktop" "development" ];
  
  modules = {
    # 禁用某些桌面功能
    "desktop.gaming" = false;
    "desktop.multimedia" = false;
    
    # 强制启用特定开发工具
    "development.cuda" = true;
    "development.docker" = true;
  };
}
```

## 优先级

模块加载的优先级（从高到低）：

1. **主机 meta.nix 的 `modules` 覆盖**（用户最高优先级）
2. **自动角色过滤**（按 `roles` 声明的模块路径）
3. **模块全局 `enable` 字段**（模块的 meta.nix）

即：`modules.enable = false` 可以禁用通过角色自动包含的任何模块。

## 向后兼容性

✓ 现有配置无需改动  
✓ 新字段完全可选  
✓ 只有需要细粒度控制的配置才需使用  

## 高级用法（未来）

### 模块级条件（计划中）

在模块自身声明条件启用：

```nix
# modules/desktop/gaming/meta.nix
{
  # 此模块默认属于 desktop 角色
  # 但也可以指定启用条件
  enableOn = { host, ... }:
    builtins.elem host [ "gaming-pc" "workstation" ];
}
```

### 模块依赖（计划中）

```nix
# modules/server/monitoring/meta.nix
{
  requiresModules = [ "server.base" ];
}
```

这些高级功能将在后续版本中实现。

## 常见问题

### Q: 如何禁用 `_common` 中的某个模块？

```nix
modules."_common.base-system" = false;
```

但不推荐这样做，因为 `_common` 通常包含必需的基础设置。

### Q: 模块名中有点号怎么办？

模块名取决于目录路径，不是文件名。如果有：

```
modules/development/python-3.11/nixos.nix
```

则模块名为 `"development.python-3.11"`。

### Q: 主机 meta.nix 中的拼写错误怎么办？

框架会：
1. 记录（警告）已知的所有模块名
2. 检测拼写错误并提示
3. 拼写错误的覆盖会被忽略（不会破坏配置）

## 迁移指南

从 0.3.x 升级到 0.4.0 时：

- 如果不需要细粒度控制，**无需做任何改动**
- 如果需要禁用某些模块，在 `hosts/xxx/meta.nix` 中添加 `modules = { ... }` 字段

## 参见

- [模块系统](./modules.md)
- [角色系统](./roles.md)
- [主机元数据](./directory-structure.md#主机元数据)
