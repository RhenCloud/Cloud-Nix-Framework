# 多主机管理

框架通过目录约定自动发现主机，无需手写 `nixosConfigurations`。

## 基本结构

```
hosts/
├── nixos-desktop/
│   ├── meta.nix
│   ├── default.nix
│   ├── hardware.nix      # 可选：硬件相关配置，自动 import
│   ├── disk.nix          # 可选：disko 或原生 fileSystems，自动 import
│   └── network.nix       # 可选：网络配置，自动 import
├── nixos-server/
│   ├── meta.nix
│   └── default.nix
└── arm-device/
    ├── meta.nix
    └── default.nix
```

每个主机目录必须在 `meta.nix` 中声明 `system`（`lib.systems.flakeExposed` 中的已知架构）。框架自动生成：

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

## 主机目录的 magic 文件（hardware / disk / network）

真实仓库的主机配置几乎总会包含硬件、磁盘、网络碎片。主机目录支持固定分拣的可选 magic 文件，**存在则按固定顺序自动 import，缺失即跳过**，不必全部堆进 `default.nix`：

```
hosts/nixos-desktop/
├── meta.nix        # 元数据（必须声明 system，不作为模块加载）
├── default.nix     # 必需：主机意图（主机名、时区、想启用的服务）
├── hardware.nix    # 可选：硬件相关配置（可在此 import nixos-hardware）
├── disk.nix        # 可选：disko 或原生 fileSystems
└── network.nix     # 可选：网络配置
```

加载顺序固定为 `default.nix → hardware.nix → disk.nix → network.nix`，与文件系统读取次序无关。这与 `modules/` 树的 `options.nix` / `default.nix` / `nixos.nix` / `home.nix` 是同一套思路：框架只负责「存在则按固定顺序 import」，**不内置、不依赖** disko / nixos-hardware；需要时在 `flake.nix` 中添加相应 input，再在 `disk.nix` / `hardware.nix` 中使用。

```nix
# hosts/nixos-desktop/disk.nix
{ inputs, ... }:
{
  imports = [ inputs.disko.nixosModules.disko ];
  disko.devices.disk.main = {
    device = "/dev/nvme0n1";
    # ...
  };
}
```

主机目录内的其他 `.nix` 文件不会被自动导入（发现阶段输出 trace 警告）；如需使用请在主机模块中自行 `import`。

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
