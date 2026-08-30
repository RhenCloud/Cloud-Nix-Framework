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
│   │   ├── default.nix                   #   中性模块：共享 option
│   │   ├── nixos.nix                     #   注入 NixOS
│   │   └── home.nix                      #   注入 home-manager
│   └── _common/networking/
│       └── nixos.nix                     #   所有角色共享的 NixOS 模块
├── packages/<name>/default.nix           # packages.<system>.<name>
├── overlays/<name>/default.nix           # overlays.<name> + 自动应用
├── apps/<name>/default.nix               # apps.<system>.<name>
├── formatter/default.nix                 # formatter.<system>
├── deploy/default.nix                    # deploy
├── lib/*.nix                             # lib.<name>
├── shells/<name>/default.nix             # devShells.<system>.<name>
├── checks/<name>/default.nix             # checks.<system>.<name>
└── secrets/                              # sops helper 约定路径
    ├── common.yaml
    └── hosts/<host>.yaml
```

## Output 映射

| 目录 | 生成的 output |
| ---- | ------------- |
| `hosts/<name>.<system>/default.nix` | `nixosConfigurations.<name>` |
| `homes/<user>/default.nix` | `homeConfigurations.<user>` |
| `homes/<user>/<host>.nix` | `homeConfigurations."<user>@<host>"` |
| `modules/**/{default,nixos,home}.nix` | 自动注入，并生成目录级 `nixosModules` / `homeModules` |
| `packages/<name>/default.nix` | `packages.<system>.<name>` |
| `packages/<name>.<system>/default.nix` | 仅对应架构的 `packages.<system>.<name>` |
| `overlays/<name>/default.nix` | `overlays.<name>`，并应用到统一包集合 |
| `apps/<name>/default.nix` | `apps.<system>.<name>` |
| `formatter/default.nix` | `formatter.<system>` |
| `deploy/default.nix` | `deploy` |
| `lib/*.nix` | `lib.<name>` |
| `shells/<name>/default.nix` | `devShells.<system>.<name>` |
| `checks/<name>/default.nix` | `checks.<system>.<name>` |

::: warning 主机目录必须带 system 后缀

`hosts/` 下的主机目录必须带 `.<system>` 后缀，例如 `nixos-desktop.x86_64-linux`。框架不猜测默认架构。

:::

## 主机与 home 自动关联

不需要在 host 中手写 `config.cloud.system` 或 `config.cloud.users`：

- 主机架构来自 `hosts/<name>.<system>/` 的目录后缀。
- `homes/<user>/<host>.nix` 自动把用户关联到该主机，并生成 `homeConfigurations."<user>@<host>"`。
- `homes/<user>/default.nix` 是共享 home，并生成 `homeConfigurations.<user>`。
- 默认关联 home 会嵌入 NixOS；`embedHomeManager = false` 时仅保留独立 home outputs。

```nix
# flake.nix
outputs = inputs:
  inputs.cloud.lib.mkFlake {
    inherit inputs;
    embedHomeManager = false;
  };
```

`cloud.users` 仍由框架根据目录写入，供模块读取，不应手动赋值。
