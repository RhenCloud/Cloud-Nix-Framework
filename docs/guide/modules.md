# 模块写作

模块采用**单树 + 文件名分拣**，一个功能只对应一个目录，消除 NixOS 与 home-manager 两棵平行树的重复。

## 三个 magic 文件

- `default.nix`：中性模块，通常声明共享 option 接口，不引用单侧专属选项。
- `nixos.nix`：NixOS 专属逻辑。
- `home.nix`：home-manager 专属逻辑。

```nix
# modules/desktop/hyprland/default.nix
{ lib, ... }:
{
  options.cloud.hyprland.enable = lib.mkEnableOption "Hyprland";
}
```

```nix
# modules/desktop/hyprland/nixos.nix
{ config, lib, ... }:
{
  config = lib.mkIf config.cloud.hyprland.enable {
    # 系统级配置
  };
}
```

```nix
# modules/desktop/hyprland/home.nix
{ config, lib, ... }:
{
  config = lib.mkIf config.cloud.hyprland.enable {
    # 用户级配置
  };
}
```

## 模块分拣规则

- NixOS 侧 = 全部 `default.nix` + `nixos.nix`。
- home-manager 侧 = 全部 `default.nix` + `home.nix`。
- 目录键由相对目录路径以 `.` 连接派生，例如 `modules/desktop/hyprland/` → `desktop.hyprland`。
- `nixosModules."desktop.hyprland"` 与 `homeModules."desktop.hyprland"` 的值是 `{ imports = [ ... ]; }`，不会暴露 `nixos.nix` 等 magic 文件名。
- 遍历按完整相对路径字典序排序，保证合并顺序稳定、可复现。
- 空目录和没有 magic 文件的叶子目录会被忽略。
- 不同路径映射到同一目录键时会在求值期报错。

## 组合角色

主机可在模块顶层声明多个角色。推荐使用 `roles`；旧的 `role = "desktop"` 继续兼容：

```nix
# hosts/nixos-desktop.x86_64-linux/default.nix
{ ... }:
{
  roles = [
    "desktop"
    "development"
  ];

  config = { };
}
```

过滤规则：

- `modules/desktop/**/nixos.nix` 和 `home.nix` 仅注入包含 `desktop` 角色的主机及其关联 home。
- `modules/development/**` 可与 desktop 同时注入。
- `modules/_common/**` 始终注入。
- 所有 `default.nix` 始终注入，保证共享 option 可见。
- 未声明 `roles` / `role` 时全量注入，保持向后兼容。

`roles` / `role` 必须是字符串列表或字符串，并位于主机模块顶层。框架交给 NixOS 前会剥离这两个元数据字段。

## 注入的模块参数

所有 NixOS、独立 home-manager 与嵌入式 home-manager 模块均自动获得：

- `inputs`：全部 flake inputs；
- `channels`：当前 `nixpkgs` 的预留解析入口；
- `self`：当前用户 flake；
- `cloud`：`patches`、`sops` 等框架 helper；
- `extraSpecialArgs` 中的自定义参数；
- 模块系统原生参数，如 `config`、`pkgs`、`lib`、`options`。

嵌入式 home-manager 的自定义参数写入 `home-manager.extraSpecialArgs`，与独立 HM 行为一致。

## 额外模块

- `extraModules`：进入每台 NixOS 主机和每个 home。
- `extraNixosModules`：仅进入 NixOS。
- `extraHomeModules`：进入独立与嵌入式 home-manager。
