# 细粒度模块控制

从 0.4.0 起，Snowveil 支持在主机级别覆盖模块的启用/禁用状态，提供比角色系统更细粒度的控制。

## 问题场景

假设有以下模块结构：

```
modules/
├── _common/
│   ├── nixos.nix           # 所有主机通用配置
│   └── home.nix            # 所有用户通用配置
├── desktop/
│   ├── nixos.nix           # desktop 基础配置
│   ├── hyprland/
│   │   └── nixos.nix       # Wayland 桌面
│   └── gaming/
│       └── nixos.nix       # 游戏相关配置
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

### 基础：按模块路径覆盖

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
modules/desktop/gaming/nixos.nix      →  "desktop.gaming"
modules/desktop/hyprland/nixos.nix    →  "desktop.hyprland"
modules/development/rust/nixos.nix    →  "development.rust"
modules/_common/base/nixos.nix        →  "_common.base"
modules/_common/nixos.nix             →  "_common"
```

**关键点**：
- 模块名称使用点号（`.`）分隔符，对应目录层级
- 设置为 `false` 会**禁用**该模块
- 设置为 `true` 会**显式启用**该模块（与默认行为相同）
- 未在 `modules` 中声明的模块使用默认行为（由角色决定）

### 场景 1：禁用某个功能模块

```nix
# hosts/work-laptop/meta.nix
{
  system = "x86_64-linux";
  roles = [ "desktop" "development" ];

  # 禁用游戏支持，保留其他 desktop 模块
  modules = {
    "desktop.gaming" = false;
  };
}
```

结果：加载 `_common`、`desktop/hyprland`、`desktop/nixos`、`development/*`，但**不加载** `desktop/gaming`。

### 场景 2：跨角色启用模块

```nix
# hosts/server/meta.nix
{
  system = "x86_64-linux";
  roles = [ "server" ];

  # 虽然没有 desktop 角色，但显式启用 hyprland
  modules = {
    "desktop.hyprland" = true;
  };
}
```

**注意**：这要求相应的模块存在且不依赖角色特定的其他模块。

### 场景 3：禁用整个角色的某类模块

```nix
# hosts/gaming-rig/meta.nix
{
  system = "x86_64-linux";
  roles = [ "desktop" "development" ];

  # 禁用多个高开销模块
  modules = {
    "development.cuda" = false;     # GPU 驱动太大
    "development.llvm" = false;     # 编译太慢
  };
}
```

## 实现原理

### 模块发现阶段

1. 框架自动发现 `modules/` 目录下的所有模块
2. 按照角色过滤（例如 `roles = ["desktop"]` 加载 `desktop/*` 和 `_common/*`）
3. **新增**：应用 `meta.nix` 中的 `modules` 覆盖

### 应用顺序

```
发现 → 角色过滤 → 应用覆盖 → 最终模块列表
```

例如对于 `roles = ["desktop"]` 和 `modules."desktop.gaming" = false`：

```
发现: [_common, desktop, desktop.gaming, desktop.hyprland, ...]
  ↓ 角色过滤
: [_common, desktop, desktop.gaming, desktop.hyprland, ...]
  ↓ 应用覆盖（desktop.gaming = false）
: [_common, desktop, desktop.hyprland, ...]
```

### 同时应用到 NixOS 和 Home Manager

模块覆盖自动应用到：
- **NixOS 侧**：`nixosModules`（`nixos.nix` 和 `default.nix`）
- **Home Manager 侧**：`homeModules`（`home.nix` 和 `default.nix`）

如果一个模块只有 `nixos.nix`，禁用它只影响 NixOS；只有 `home.nix` 则只影响 Home Manager。

## 常见模式

### 模式 1：按主机禁用可选功能

```nix
# modules/desktop/nvidia/
├── default.nix
├── nixos.nix
└── meta.nix  # 可选

# hosts/laptop/meta.nix
{
  system = "x86_64-linux";
  roles = [ "desktop" ];
  modules = {
    "desktop.nvidia" = false;  # 集显笔记本
  };
}

# hosts/gaming-desktop/meta.nix
{
  system = "x86_64-linux";
  roles = [ "desktop" ];
  # 没有覆盖，默认启用 desktop.nvidia
}
```

### 模式 2：渐进式功能开发

在开发新模块时，可以暂时禁用它：

```nix
# hosts/nixos-desktop/meta.nix
{
  system = "x86_64-linux";
  roles = [ "desktop" ];
  modules = {
    "desktop.wayland-experimental" = false;  # WIP
  };
}
```

### 模式 3：系统特定的排除

某个模块可能不支持所有架构：

```nix
# modules/development/cuda/default.nix
{ config, pkgs, lib, ... }:
{
  # CUDA 目前只支持 x86_64-linux
  config = lib.mkIf config.snowveil.roles.development.enable {
    nixpkgs.config.cudaSupport = true;
    # ...
  };
}

# hosts/aarch64-server/meta.nix
{
  system = "aarch64-linux";
  roles = [ "development" ];
  modules = {
    "development.cuda" = false;  # 不支持 ARM64
  };
}
```

## 错误处理

### 无效的模块覆盖

如果在 `meta.nix` 中指定了不存在的模块，系统**不会报错**（silent ignore），因为模块是动态发现的。这允许在不同的配置或 Git 分支间共享 `meta.nix`。

### 禁用 _common 模块

```nix
# hosts/minimal/meta.nix
{
  system = "x86_64-linux";
  roles = [];
  modules = {
    "_common.heavy-build-tools" = false;  # 禁用可选的通用工具
  };
}
```

这是完全支持的——即使 `_common` 模块默认总是加载，覆盖也会生效。

## 迁移指南

### 从 mkForce 到 modules 覆盖

**之前**（v0.3 及更早）：

```nix
# hosts/server/default.nix
{
  imports = [ ... ];

  # 手动排除某些配置
  services.display-manager.enable = lib.mkForce false;
}
```

**现在**（v0.4+）：

```nix
# hosts/server/meta.nix
{
  system = "x86_64-linux";
  roles = [ "server" ];
  modules = {
    "desktop.display-manager" = false;  # 更清晰
  };
}
```

## 常见问题

**Q: 如果我禁用一个模块，依赖于它的其他模块会怎样？**

A: 框架只负责加载/不加载模块文件。如果模块A依赖模块B但B被禁用，会在求值时报错。建议在模块内使用条件加载：

```nix
# modules/desktop/games-nvidia/default.nix
{
  imports = lib.optionals config.snowveil.roles.desktop.nvidia.enable [
    ./nvidia-games.nix
  ];
}
```

**Q: 能否在 `default.nix` 中动态决定启用哪些模块？**

A: 当前不支持。`meta.nix` 是静态元数据，在主机配置求值前读取。如需动态决策，使用：

```nix
# hosts/nixos-desktop/default.nix
{ config, lib, ... }:
{
  imports = [
    (lib.optionalModule config.myconfig.enableGaming ./gaming-config.nix)
  ];

  config.myconfig.enableGaming = true;
}
```

**Q: 覆盖的优先级是什么？**

A: 
1. 通过 `modules` 覆盖显式设置为 `false` → **禁用**
2. 通过 `modules` 覆盖显式设置为 `true` → **启用**
3. 默认行为（由 roles 决定）

**Q: 我想完全禁用某个角色。应该用什么？**

A: 不把它加到 `roles`，而不是在 `modules` 中逐个禁用：

```nix
# ✗ 不推荐
{
  roles = [ "desktop" "development" ];
  modules = {
    "desktop.*" = false;  # 不支持通配符！
  };
}

# ✓ 推荐
{
  roles = [ "development" ];  # 直接移除 desktop
}
```

## 变更日志

### v0.4.0
- 新增：`meta.nix` 中的 `modules` 字段支持细粒度模块覆盖
- 新增：`moduleTools.validateModuleOverrides()` 验证覆盖配置
- 新增：`snowveil.lib.version` 支持 feature detection
