# 目录结构

一个标准的用户配置仓库长这样：

```
.
├── flake.nix                             # 唯一入口
├── hosts/                                # NixOS 主机
│   └── nixos-desktop.x86_64-linux/
│       └── default.nix                   #   -> nixosConfigurations.nixos-desktop
├── homes/                                # home-manager 用户
│   └── rhencloud/
│       ├── default.nix                   #   -> homeConfigurations.rhencloud
│       └── nixos-desktop.nix             #   -> homeConfigurations."rhencloud@nixos-desktop"
├── modules/                              # 可复用模块（单树，自动分拣）
│   ├── desktop/hyprland/
│   │   ├── default.nix                   #   中性模块：声明共享 option
│   │   ├── nixos.nix                     #   注入 NixOS
│   │   └── home.nix                      #   注入 home-manager
│   └── shell/fish/
│       ├── default.nix
│       └── home.nix                      #   仅 HM 侧，可无 nixos.nix
├── packages/                             # 自定义包
│   └── <name>/default.nix
├── overlays/                             # overlays（含 patch 逻辑）
│   └── <name>/default.nix
├── lib/                                  # 项目级工具库
├── shells/<name>/default.nix             # devShells
├── checks/<name>/default.nix             # flake checks
└── secrets/                              # sops（common.yaml + hosts/<host>.yaml）
```

## Output 映射

每个目录层级都映射到一个 flake output：

| 目录 | 生成的 output |
| ---- | ------------- |
| `hosts/<name>.<system>/default.nix` | `nixosConfigurations.<name>` |
| `homes/<user>/default.nix` | `homeConfigurations.<user>` |
| `homes/<user>/<host>.nix` | `homeConfigurations."<user>@<host>"` |
| `modules/**/{default,nixos,home}.nix` | 自动注入两侧模块列表 |
| `packages/<name>/default.nix` | `packages.<name>`（另支持 `packages/<name>.<system>` 单架构） |
| `overlays/<name>/default.nix` | `overlays.<name>` |
| `lib/` | `lib` |
| `shells/<name>/default.nix` | `devShells.<system>.<name>` |
| `checks/<name>/default.nix` | `checks.<system>.<name>` |

::: warning 主机目录必须带 system 后缀

`hosts/` 下的主机目录**必须**带 `.<system>` 后缀（如 `nixos-desktop.x86_64-linux`），framework 不猜测默认架构。

:::

## 主机声明用户

`hosts/<name>.<system>/default.nix` 通过 `config.cloud.users` 声明该主机构建哪些 home（对应生成 `<user>@<host>`，并内嵌进系统配置）：

```nix
# hosts/nixos-desktop.x86_64-linux/default.nix
{ config, ... }: {
  config.cloud = {
    system = "x86_64-linux";
    users = [ "rhencloud" ];
  };
}
```