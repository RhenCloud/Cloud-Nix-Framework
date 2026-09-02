# Home Manager 集成

框架支持两种 Home Manager 使用方式：**嵌入式**（挂载到 NixOS 主机）与**独立式**（`home-manager switch`）。

## 目录约定

```
homes/
├── rhencloud/
│   ├── default.nix          # 共享 home → homeConfigurations.rhencloud
│   ├── nixos-desktop.nix    # 主机关联 → homeConfigurations."rhencloud@nixos-desktop"
│   └── nixos-server.nix     # 主机关联 → homeConfigurations."rhencloud@nixos-server"
└── work/
    └── default.nix          # homeConfigurations.work
```

`<host>.nix` 的文件名必须与 `hosts/` 中已发现的主机名完全一致，否则静默忽略。

## 嵌入式 HM

当 `homes/<user>/<host>.nix` 存在时，框架自动将该用户注入 `nixosConfigurations.<host>` 的 `config.snowveil.users`，并在嵌入启用时生成 `home-manager.users.<user>` 配置，无需手写。

全局启用，单独关闭：

```nix
# flake.nix
outputs = inputs:
  inputs.snowveil.lib.mkFlake {
    inherit inputs;

    home.embed = {
      default = true;
      hosts.yc-hk-1 = false;  # 该主机不嵌入
    };
  };
```

或在主机 `meta.nix` 中声明：

```nix
# hosts/yc-hk-1.x86_64-linux/meta.nix
{
  home.embed = false;
}
```

关闭嵌入后，`homeConfigurations."rhencloud@yc-hk-1"` 仍会生成，可以通过 `home-manager switch` 激活。

## 模块共享

`modules/` 下的 `default.nix` 与 `home.nix` 同时注入 NixOS 和 home-manager，一个目录覆盖两侧：

```nix
# modules/desktop/hyprland/default.nix（共享 option 声明）
{ lib, ... }:
{
  options.snowveil.hyprland.enable = lib.mkEnableOption "Hyprland";
}
```

```nix
# modules/desktop/hyprland/home.nix（用户级配置）
{ config, lib, ... }:
{
  config = lib.mkIf config.snowveil.hyprland.enable {
    wayland.windowManager.hyprland.enable = true;
  };
}
```

## useGlobalPkgs 与 Stylix

框架默认使用 `home-manager.useGlobalPkgs = true`（HM 复用 NixOS 的 pkgs）。Stylix 等需要在 HM 侧添加 overlay 的模块会触发 HM 弃用警告。

解决方法：在需要的主机上关闭 `useGlobalPkgs`：

```nix
# hosts/nixos-desktop/meta.nix
{
  home.useGlobalPkgs = false;
}
```

框架关闭后会自动将 `nixpkgs.config` 与 overlays 注入 HM 自己的 nixpkgs，维持统一配置。

## 独立 HM 切换

```bash
# 全局 home（system 取 systems 首项）
home-manager switch --flake .#rhencloud

# 主机关联 home
home-manager switch --flake .#rhencloud@nixos-desktop
```

::: warning 全局 home 的 system 限制

`homeConfigurations.rhencloud` 使用 `systems` 第一个元素作为 system。若需要多架构，使用关联主机的 `<host>.nix` 形式。

:::
