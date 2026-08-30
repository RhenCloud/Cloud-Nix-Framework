# 目录结构

一个标准的用户配置仓库长这样：

```text
.
├── flake.nix
├── hosts/
│   ├── nixos-desktop.x86_64-linux/       # 目录名带 system 后缀（推荐）
│   │   ├── meta.nix                      # 角色与框架元数据
│   │   └── default.nix                   # nixosConfigurations.nixos-desktop
│   └── my.host.example.com/              # FQDN 主机名：在 meta.nix 中声明 system
│       ├── meta.nix                      # { system = "x86_64-linux"; roles = [...]; }
│       └── default.nix
├── homes/
│   └── rhencloud/
│       ├── default.nix                   # homeConfigurations.rhencloud
│       └── nixos-desktop.nix             # homeConfigurations."rhencloud@nixos-desktop"
├── modules/**/{default,nixos,home}.nix
├── packages/
│   ├── <name>/default.nix
│   ├── <name>/meta.nix                   # 可选：enable / systems
│   └── <system>/<name>/default.nix       # 明确的单架构约定
├── overlays/<name>/default.nix
├── apps/<name>/default.nix
├── formatter/default.nix
├── deploy/default.nix
├── lib/*.nix
├── shells/<name>/default.nix
├── checks/<name>/default.nix
└── secrets/
    ├── common.yaml
    └── hosts/<host>.yaml
```

## Output 映射

| 目录 | 生成的 output |
| ---- | ------------- |
| `hosts/<name>.<system>/default.nix` 或 `hosts/<name>/default.nix`（含 `meta.nix { system }`）| `nixosConfigurations.<name>` |
| `hosts/<name>.<system>/meta.nix` | 角色与每主机 Home Manager 策略，不直接生成 output |
| `homes/<user>/default.nix` | `homeConfigurations.<user>` |
| `homes/<user>/<host>.nix` | `homeConfigurations."<user>@<host>"` |
| `modules/**/{default,nixos,home}.nix` | 自动注入，并生成目录级 `nixosModules` / `homeModules` |
| `packages/<name>/default.nix` | `packages.<system>.<name>` |
| `packages/<system>/<name>/default.nix` | 仅对应架构的 `packages.<system>.<name>` |
| `packages/<name>.<system>/default.nix` | 旧式单架构约定，继续兼容 |
| `overlays/<name>/default.nix` | `overlays.<name>`，并应用到统一包集合 |
| `apps/<name>/default.nix` | `apps.<system>.<name>` |
| `formatter/default.nix` | `formatter.<system>` |
| `deploy/default.nix` | `deploy` |
| `lib/*.nix` | `lib.<name>` |
| `shells/<name>/default.nix` | `devShells.<system>.<name>` |
| `checks/<name>/default.nix` | `checks.<system>.<name>` |

::: warning 主机目录 system 解析规则

`hosts/` 下的主机目录按以下优先级推断 system：

1. **目录后缀**（推荐）：`nixos-desktop.x86_64-linux/` — 后缀必须是 `lib.systems.flakeExposed` 中的已知 system。
2. **`meta.nix` 声明**：无后缀目录可在 `meta.nix` 中写 `{ system = "x86_64-linux"; }`。

两种形式可共存。不满足任一条件的目录会输出 `trace` 警告并跳过，不会报错中止。FQDN 形式的主机名（含多个点号）建议使用 `meta.nix` 声明 system，避免后缀解析歧义。

:::

## 主机元数据

推荐把角色和框架策略放在独立的 `meta.nix`：

```nix
# hosts/yc-hk-1.x86_64-linux/meta.nix
{
  roles = [ "server" ];

  home = {
    embed = false;
    useGlobalPkgs = false;
  };
}
```

角色同时支持单字符串 `role`（与 `roles` 互为别名）。主机元数据优先于 `mkFlake` 的全局策略。旧字段 `embedHomeManager`、`homeManagerUseGlobalPkgs`、`homeManager.embed`、`homeManager.useGlobalPkgs` 仍兼容，但已弃用，会输出 trace 警告。

`meta.nix` 必须直接返回属性集，不是 NixOS module，也不会收到 `config` 等模块参数。框架读取它以后，`default.nix` 只由 NixOS module system 正式求值，可以在外层安全使用真实 `config`：

```nix
# hosts/yc-hk-1.x86_64-linux/default.nix
{ config, ... }:
{
  services.openssh.ports = [
    config.rhencloud.server.ssh.port
  ];
}
```

`default.nix` 是纯 NixOS 模块，不再被框架解析框架元数据。新配置请始终使用 `meta.nix` 声明角色和框架策略。

## 主机与 home 自动关联

- 主机架构来自 `hosts/<name>.<system>/` 的目录后缀。
- `homes/<user>/<host>.nix` 自动把用户关联到该主机，并生成 `homeConfigurations."<user>@<host>"`。
- `homes/<user>/default.nix` 是共享 home，并生成 `homeConfigurations.<user>`。
- `home.embed = false` 只关闭该主机的嵌入式 HM，独立 home output 仍然保留。

全局也可使用 per-host 策略：

```nix
outputs = inputs:
  inputs.cloud.lib.mkFlake {
    inherit inputs;

    home.embed = {
      default = true;
      hosts.yc-hk-1 = false;
    };
  };
```

主机 `meta.nix` 中的设置优先于全局策略。`cloud.users` 仍由框架根据目录写入，供模块读取，不应手动赋值。

## Package 元数据

`packages/<name>/meta.nix` 可显式控制架构并消除点号歧义：

```nix
{
  systems = [ "x86_64-linux" ];
  enable = true;
}
```

若包名本身是 `foo.x86_64-linux`，存在 `meta.nix` 且显式声明 `systems` 时，完整目录名会被保留为包名，不再按旧后缀规则拆分。
