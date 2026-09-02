# 多主机管理

框架通过目录约定自动发现主机，无需手写 `nixosConfigurations`。

## 基本结构

```
hosts/
├── nixos-desktop.x86_64-linux/
│   ├── meta.nix
│   └── default.nix
├── nixos-server.x86_64-linux/
│   ├── meta.nix
│   └── default.nix
└── arm-device.aarch64-linux/
    ├── meta.nix
    └── default.nix
```

每个子目录必须带有 `.<system>` 后缀（`lib.systems.flakeExposed` 中的已知架构）。框架自动生成：

```
nixosConfigurations.nixos-desktop
nixosConfigurations.nixos-server
nixosConfigurations.arm-device
```

## 主机元数据

在 `meta.nix` 中声明角色和主机级策略（不是 NixOS 模块，不接受 `config` 参数）：

```nix
# hosts/nixos-desktop/meta.nix
{
  roles = [
    "desktop"
    "development"
  ];

  home.embed = true;
  home.useGlobalPkgs = false;  # 允许 Stylix 等 HM 模块添加 overlay
}
```

```nix
# hosts/nixos-server/meta.nix
{
  roles = [ "server" ];
  home.embed = false;  # 服务器无 HM 嵌入
}
```

## default.nix 是纯 NixOS 模块

`default.nix` 只交给 NixOS module system 求值，可以在外层直接使用真实 `config`：

```nix
# hosts/nixos-desktop/default.nix
{ config, pkgs, lib, ... }:
{
  networking.hostName = "nixos-desktop";
  # 可以在这里直接引用 config 的其他属性
}
```

## 多主机共享配置

公共配置通过 `modules/_common/` 自动注入所有主机：

```
modules/
├── _common/
│   ├── base/
│   │   ├── nixos.nix     # 所有 NixOS 主机都会加载
│   │   └── home.nix      # 所有 home 都会加载
│   └── security/
│       └── nixos.nix
├── desktop/
│   └── hyprland/
│       ├── nixos.nix     # 仅 roles 含 "desktop" 的主机
│       └── home.nix
└── server/
    └── nginx/
        └── nixos.nix     # 仅 roles 含 "server" 的主机
```

## 构建与切换

```bash
# 构建指定主机
nixos-rebuild switch --flake .#nixos-desktop

# 构建所有主机（CI）
nix flake check path:. --show-trace

# 查看发现到的主机
nix build .#checks.x86_64-linux.snowveil-discovery && cat result
```

## FQDN 主机名

含多个点号的主机名（如 `prod.db.internal`）会导致后缀解析歧义，建议使用无后缀目录 + `meta.nix`：

```
hosts/prod.db.internal/
├── meta.nix    # 含 system = "x86_64-linux";
└── default.nix
```
