# 从 snowfallorg/lib 迁移

## 相似点

- 同样使用目录约定自动发现主机、模块、包
- 同样支持 NixOS + home-manager 双轨
- 同样有 `specialArgs` 注入机制

## 主要差异

| | snowfallorg/lib | Snowveil |
| ---- | ---- | ---- |
| 模块树 | NixOS 树 / HM 树分开 | 单树 + 文件名分拣 |
| 角色过滤 | 无内置 | `roles` + 目录前缀 |
| meta.nix | 无 | 有（主机级策略） |
| 运行时依赖 | flake-utils-plus | 纯 nixpkgs.lib |

## 迁移目录结构

**snowfall 结构**：

```
modules/
├── nixos/
│   └── desktop/hyprland/default.nix
└── home/
    └── desktop/hyprland/default.nix
```

**Snowveil 结构**：

```
modules/
└── desktop/
    └── hyprland/
        ├── nixos.nix   # 原 nixos/ 树内容
        └── home.nix    # 原 home/ 树内容
```

共享 option 声明放 `default.nix`：

```
modules/desktop/hyprland/default.nix  # lib.mkEnableOption 等
```

## 迁移 systems

snowfall 通常在 `lib.mkFlake` 的 `channels` 或 `systems` 中声明架构，Snowveil 从目录后缀或 `meta.nix` 提取：

```
# snowfall 主机目录
systems/x86_64-linux/nixos-desktop/default.nix

# Snowveil 主机目录
hosts/nixos-desktop.x86_64-linux/default.nix
```

## flake.nix 对比

**snowfall**：

```nix
outputs = inputs:
  inputs.snowfall-lib.mkFlake {
    inherit inputs;
    src = ./.;
    snowfall.namespace = "myns";
  };
```

**Snowveil**：

```nix
outputs = inputs:
  inputs.snowveil.lib.mkFlake {
    inherit inputs;
  };
```

## namespace 对应

snowfall 的 `namespace` 在 Snowveil 中没有直接对应。Snowveil 模块通常使用 `snowveil.<feature>.enable` 或自定义命名空间（如 `myns.<feature>.enable`）；option 声明放在各模块的 `default.nix` 中。
