# 目录结构

一个标准的用户配置仓库长这样：

```text
.
├── flake.nix
├── hosts/
│   ├── nixos-desktop/
│   │   ├── meta.nix                      # 必须声明 system 和其他角色/策略
│   │   └── default.nix                   # nixosConfigurations.nixos-desktop
│   └── my-host-fqdn/
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
| `hosts/<name>/default.nix` | `nixosConfigurations.<name>` |
| `hosts/<name>/meta.nix` | 角色与每主机 Home Manager 策略，**必须声明 `system`** |
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

## 主机命名与 System 声明

从 0.4.0 起，hosts 目录改用裸名称：`hosts/<name>/`，system 必须在 `meta.nix` 中显式声明。

**不再支持**的方式：
- `hosts/nixos-desktop.x86_64-linux/` ❌（旧格式，不再解析后缀）

**唯一支持**的方式：
- `hosts/nixos-desktop/` ✅（必须在 `meta.nix` 中写 `system = "x86_64-linux"`）

这消除了目录名中的点号歧义（FQDN 型主机名不再造成困惑），并明确表达 system 的强制要求。

## 主机元数据

推荐把角色和框架策略放在独立的 `meta.nix`：

```nix
# hosts/nixos-desktop/meta.nix
{
  system = "x86_64-linux";  # 必须，指定此主机的系统架构
  roles = [ "desktop" "development" ];

  home = {
    embed = true;             # 是否嵌入式 Home Manager
    useGlobalPkgs = false;    # Home Manager useGlobalPkgs 设置
  };
}
```

主机元数据优先于 `mkFlake` 的全局策略。旧字段 `embedHomeManager`、`homeManagerUseGlobalPkgs`、`homeManager.embed`、`homeManager.useGlobalPkgs` 仍兼容，但已弃用，会输出 trace 警告。

`meta.nix` 必须直接返回属性集，不是 NixOS module，也不会收到 `config` 等模块参数。框架读取它以后，`default.nix` 只由 NixOS module system 正式求值，可以在外层安全使用真实 `config`：

```nix
# hosts/nixos-desktop/default.nix
{ config, ... }:
{
  services.openssh.ports = [
    config.rhencloud.server.ssh.port
  ];
}
```

`default.nix` 是纯 NixOS 模块，不再被框架解析框架元数据。新配置请始终使用 `meta.nix` 声明 system、角色和框架策略。

## 主机与 home 自动关联

- `homes/<user>/<host>.nix` 自动把用户关联到该主机，并生成 `homeConfigurations."<user>@<host>"`。
- `homes/<user>/default.nix` 是共享 home，并生成 `homeConfigurations.<user>`。
- `home.embed = false` 只关闭该主机的嵌入式 HM，独立 home output 仍然保留。

全局也可使用 per-host 策略：

```nix
outputs = inputs:
  inputs.snowveil.lib.mkFlake {
    inherit inputs;

    home.embed = {
      default = true;
      hosts.yc-hk-1 = false;
    };
  };
```

主机 `meta.nix` 中的设置优先于全局策略。`snowveil.users` 仍由框架根据目录写入，供模块读取，不应手动赋值。

## Package 元数据

`packages/<name>/meta.nix` 可显式控制架构并消除点号歧义：

```nix
{
  systems = [ "x86_64-linux" ];
  enable = true;
}
```

若包名本身是 `foo.x86_64-linux`，存在 `meta.nix` 且显式声明 `systems` 时，完整目录名会被保留为包名，不再按旧后缀规则拆分。
