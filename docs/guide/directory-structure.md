# 目录结构

一个标准的用户配置仓库长这样：

```text
.
├── flake.nix
├── hosts/
│   ├── nixos-desktop/
│   │   ├── meta.nix                      # 必须声明 system 和其他角色/策略
│   │   ├── default.nix                   # nixosConfigurations.nixos-desktop
│   │   ├── hardware.nix                  # 可选：硬件配置，存在则自动 import
│   │   ├── disk.nix                      # 可选：磁盘布局（disko / fileSystems），自动 import
│   │   └── network.nix                   # 可选：网络配置，存在则自动 import
│   └── my-host-fqdn/
│       ├── meta.nix                      # { system = "x86_64-linux"; roles = [...]; }
│       └── default.nix
├── users/
│   └── rhencloud/
│       ├── meta.nix                      # 声明 hosts、uid、组、密码等
│       └── default.nix                   # 可选：users.users.rhencloud 补充
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
| `hosts/<name>/{hardware,disk,network}.nix` | 可选：主机目录 magic 文件，存在则按固定顺序随主机自动 import |
| `hosts/<name>/meta.nix` | 角色与每主机 Home Manager 策略，**必须声明 `system`** |
| `users/<name>/meta.nix` | 声明用户属性，自动生成 `users.users.<name>` / `users.groups.<name>` |
| `users/<name>/default.nix` | 可选：`users.users.<name>` 补充模块 |
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

## 用户（一等实体）

用户由 `users/<name>/` 目录声明，是框架的一等实体，不再是 `homes/<user>/<host>.nix` 的推导结果。`users/<name>/meta.nix` 是用户与主机关联的**唯一来源**：

```nix
# users/rhencloud/meta.nix
{
  hosts = [ "nixos-desktop" "hm-standalone" ];  # 必需：此用户关联的主机
  uid = 1000;
  extraGroups = [ "wheel" ];
  hashedPasswordSecret = "rhencloud-password";  # sops 密钥名，或 "/字面/路径"
}
```

框架在对应主机自动生成 `users.users.<name>` 与 `users.groups.<name>`（`isNormalUser`、`home`、`createHome`、`group`、`uid`、`extraGroups`、`description`、`hashedPasswordFile`），默认值均用 `mkDefault` 包裹，可被 `users/<name>/default.nix` 或主机模块覆盖：

- `hashedPasswordSecret` 以 `/` 开头 → 视为字面文件路径，直接作为 `hashedPasswordFile`。
- 否则 → sops 密钥名，`hashedPasswordFile` 指向 `config.sops.secrets.<name>.path`，并自动声明 `sops.secrets.<name>`（来源主机文件）。
- `users/<name>/default.nix`（可选）是补充模块，用于覆写自动生成字段或追加其他 `users.users.<name>` 属性。

## 主机与 home 自动关联

- `homes/<user>/<host>.nix` 把用户的 home 配置关联到该主机，并生成 `homeConfigurations."<user>@<host>"`。
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

主机 `meta.nix` 中的设置优先于全局策略。`snowveil.users` 仍由框架根据 `users/<name>/meta.nix` 的 `hosts` 写入，供模块读取，不应手动赋值。

## Package 元数据

`packages/<name>/meta.nix` 可显式控制架构并消除点号歧义：

```nix
{
  systems = [ "x86_64-linux" ];
  enable = true;
}
```

若包名本身是 `foo.x86_64-linux`，存在 `meta.nix` 且显式声明 `systems` 时，完整目录名会被保留为包名，不再按旧后缀规则拆分。
