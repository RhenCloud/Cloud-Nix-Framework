# Cloud Nix Framework

基于 Nix Flakes 的声明式配置框架，融合三个优秀项目的设计理念：

| 参考项目 | 借鉴的设计 |
| -------- | ---------- |
| [flake.parts](https://flake.parts/) | 模块化、声明式、可组合的配置方式 |
| [snowfallorg/lib](https://github.com/snowfallorg/lib) | 统一管理系统 / 模块 / 主机配置，分类自动发现 |
| [flake-fhs](https://github.com/luochen1990/flake-fhs) | 「目录即 Flake」，按约定组织目录自动生成 outputs |

核心目标：**用约定代替样板（convention over configuration）**，让多主机、多用户的 NixOS + home-manager 配置仓库结构清晰、可复用、易上手。

完整文档见 [docs/](./docs/)（VitePress 站点，本地预览 `cd docs && npm run docs:dev`）。

## 设计理念

- **约定优于配置**：目录层级即配置意图，无需手写 import 列表与 output 拼接。
- **纯 `nixpkgs.lib`**：框架自身零 `flake-utils` / `flake.parts` 运行时依赖，`forAllSystems` 与文件系统遍历自实现。
- **双对象**：同时覆盖 NixOS（系统级）与 home-manager（用户级），且二者共享同一模块来源，避免重复。
- **分层入口**：`mkFlake` 覆盖常规场景，`mkSystem` / `mkHome` 作为细粒度逃生舱，兼顾零样板与例外处理。
- **无侵入、渐进式**：作为独立 flake input 引入，可平滑迁移既有配置。

## 实现进度

| 组件 | 路径 | 内容 | 状态 |
| ---- | ---- | ---- | ---- |
| 核心库 | `lib/default.nix` | `mkFlake` / `mkSystem` / `mkHome` / `mkLib` | 完成 |
| 文件系统发现 | `lib/fs.nix` | `importModules` / `flattenTree` | 完成 |
| Patch helper | `lib/patches.nix` | `cloud.patches.local` / `fromPR` | 完成 |
| Flake 入口 | `flake.nix` | 暴露 `lib` / `templates` / `checks` | 完成 |
| 模板 | `templates/default/` | `nix flake init --template` | 完成 |
| 示例 | `examples/` | 可运行的最小示例 | 完成 |
| 自检 | `checks/` | `nix flake check` | 完成 |
| 文档 | `README.md` / `AGENTS.md` | 项目说明与开发约定 | 完成 |

## 快速开始

### 1. 初始化模板

```bash
nix flake init --template github:RhenCloud/Cloud-Nix-Framework
```

### 2. 目录结构

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
├── apps/<name>/default.nix               # apps.<system>.<name>
├── formatter/default.nix                 # formatter.<system>
├── deploy/default.nix                    # deploy / deploy-rs 配置
├── lib/                                  # 项目级工具库
├── shells/<name>/default.nix             # devShells
├── checks/<name>/default.nix             # flake checks
└── secrets/                              # sops（common.yaml 或 hosts/<host>.yaml）
```

每个目录层级都映射到一个 flake output：

| 目录 | 生成的 output |
| ---- | ------------- |
| `hosts/<name>.<system>/default.nix` | `nixosConfigurations.<name>` |
| `homes/<user>/default.nix` | `homeConfigurations.<user>` |
| `homes/<user>/<host>.nix` | `homeConfigurations."<user>@<host>"` |
| `modules/**/{default,nixos,home}.nix` | 自动注入，并生成 `nixosModules.<目录键>` / `homeModules.<目录键>` |
| `packages/<name>/default.nix` | `packages.<system>.<name>`（另支持 `packages/<name>.<system>` 单架构） |
| `overlays/<name>/default.nix` | `overlays.<name>`，并自动应用到框架创建的全部包集合 |
| `apps/<name>/default.nix` | `apps.<system>.<name>` |
| `formatter/default.nix` | `formatter.<system>` |
| `deploy/default.nix` | `deploy` |
| `lib/*.nix` | `lib.<name>` |
| `shells/<name>/default.nix` | `devShells.<system>.<name>` |
| `checks/<name>/default.nix` | `checks.<system>.<name>` |

> `hosts/` 下的主机目录**必须**带 `.<system>` 后缀（如 `nixos-desktop.x86_64-linux`），framework 不猜测默认架构。

### 3. flake.nix 最小示例

```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    home-manager.url = "github:nix-community/home-manager";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";
    cloud.url = "github:RhenCloud/Cloud-Nix-Framework";
    cloud.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = inputs: inputs.cloud.lib.mkFlake {
    inherit inputs;
  };
}
```

仅凭这一段，`hosts/`、`homes/`、`modules/`、`packages/`、`overlays/`、`apps/`、`formatter/`、`deploy/`、`lib/`、`shells/`、`checks/` 下的内容就会被自动解析成完整配置。

## 核心 API

框架通过 flake 的 `lib` 输出暴露统一命名空间。用户 flake 中应从 `inputs.cloud.lib` 调用，完整入口是 `inputs.cloud.lib.mkFlake`。

### `mkFlake`

顶层 outputs 构造器，自动扫描目录并拼接全部 outputs：

```nix
inputs.cloud.lib.mkFlake {
  inherit inputs;
  root = ./.; # 可选；通常自动推导，封装调用时可显式指定
  systems = [ "x86_64-linux" "aarch64-linux" ];
  extraOutputs = { };
  extraSpecialArgs = { };
  extraModules = [ ];
  extraNixosModules = [ ];
  extraHomeModules = [ ];
  nixpkgsConfig = { allowUnfree = true; };
  extraOverlays = [ ];
  embedHomeManager = true;
  moduleRegistries = [ ];
}
```

- `root`：配置仓库根目录，通常从 `mkFlake` 调用位置自动推导；经自定义 helper 封装调用时可显式传入 `./.`。
- `systems`：生成 `packages`、`checks`、`devShells`、`apps`、`formatter` 等 per-system outputs 的架构列表。
- `extraOutputs`：与自动生成 outputs 深度合并，作为不符合目录约定时的逃生舱。
- `extraSpecialArgs`：注入 NixOS、独立 home-manager 和嵌入式 home-manager；嵌入场景写入 `home-manager.extraSpecialArgs`。
- `extraModules`：同时追加到每台 NixOS 主机和每个 home。
- `extraNixosModules` / `extraHomeModules`：仅追加到对应一侧；`extraHomeModules` 同时作用于独立与嵌入式 home。
- `nixpkgsConfig`：统一设置 `allowUnfree`、`permittedInsecurePackages` 等 nixpkgs 配置。
- `extraOverlays`：在自动发现的 overlays 之后追加额外 overlay。
- `embedHomeManager`：默认 `true`；设为 `false` 时仍生成独立 `homeConfigurations`，但不向 NixOS 导入或嵌入 home-manager。
- `moduleRegistries`：按需并入外部模块注册表。

### `mkSystem`

`mkSystem` / `mkHome` 需要先通过 `mkLib { inherit inputs; }` 绑定当前用户 flake；它们不是框架 input 上的未绑定函数。

创建单个 `nixosConfigurations.<host>`：

```nix
outputs = inputs:
  let
    cloud = inputs.cloud.lib.mkLib { inherit inputs; };
  in
  {
    nixosConfigurations.nixos-desktop = cloud.mkSystem {
      host = "nixos-desktop";
      system = "x86_64-linux"; # 可为 null，从 hosts/<host>.<system>/ 派生
      modules = [ ];
      extraModules = [ ];
      extraNixosModules = [ ];
      extraHomeModules = [ ];
      extraSpecialArgs = { };
      nixpkgsConfig = { };
      extraOverlays = [ ];
      embedHomeManager = true;
    };
  };
```

### `mkHome`

创建单个 `homeConfigurations.<user>` 或 `homeConfigurations."<user>@<host>"`：

```nix
outputs = inputs:
  let
    cloud = inputs.cloud.lib.mkLib { inherit inputs; };
  in
  {
    homeConfigurations."rhencloud@nixos-desktop" = cloud.mkHome {
      user = "rhencloud";
      host = "nixos-desktop";  # null = 全局 home；非 null 时继承对应主机架构
      system = "x86_64-linux"; # 仅全局 home 使用
      modules = [ ];
      extraModules = [ ];
      extraHomeModules = [ ];
      extraSpecialArgs = { };
      nixpkgsConfig = { };
      extraOverlays = [ ];
    };
  };
```

> ⚠️ **全局 home 的构建架构**：`mkFlake` 生成 `homeConfigurations.<user>` 时默认取 `systems` 首项。若本机架构不是首项，请调整顺序或用 `mkHome { system = "aarch64-linux"; }` 显式声明。

### `mkLib` / 自动发现函数 / patch 与 sops helper

- `mkLib { inherit inputs; }` 返回已绑定当前 flake 的 `cloud` 命名空间。
- `importModules` / `flattenTree` / `groupModules` 是目录自动发现工具函数，按完整相对路径字典序稳定遍历。
- `cloud.patches.local` / `cloud.patches.fromPR` 提供 patch helper。
- `cloud.sops.commonFile` / `hostFile` / `defaultFile` / `mkModule` 提供显式的 sops-nix 接入助手。

### 注入的模块参数

所有模块（NixOS、独立 home-manager 与嵌入式 home-manager）均自动获得：`inputs`、`channels`、`self`、`cloud`，以及对应模块系统的原生参数。`extraSpecialArgs` 会合并到这组参数中。

### 求值模型

框架对每台主机 / 每个 home 都只做**单次求值**。主机与用户关联、要嵌入哪些 home，均通过目录结构在求值前推导：

- **NixOS 主机**：从 `hosts/<name>.<system>/` 后缀得到 `system`。
- **per-host home**：`"<user>@<host>"` 继承对应主机架构。
- **全局 home**：由 `mkHome.system` 指定；`mkFlake` 默认使用 `systems` 首项。

### 镜像生成

框架基于 nixpkgs 原生 `image.modules` / `system.build.images`，按主机声明生成 `images.<host>.<format>`，不计入 checks：

```nix
# hosts/nixos-desktop.x86_64-linux/default.nix
{ ... }:
{
  config.cloud.images.formats = [ "iso" "raw" "oci" ];
}
```

若声明的变体在当前 nixpkgs 不存在，框架会在求值期抛出明确错误。

### 模块注册表（opt-in）

`moduleRegistries` 可并入外部模块源。注册表 flake 应暴露 `{ modules = { nixos = [ ... ]; home = [ ... ]; }; }`；注册表模块先于本地模块进入列表：

```nix
outputs = inputs:
  inputs.cloud.lib.mkFlake {
    inherit inputs;
    moduleRegistries = [ inputs.cloudModules.example ];
  };
```

### 组合角色过滤（opt-in）

主机可在 `hosts/<name>.<system>/default.nix` **顶层**声明多个角色。`roles` 是推荐写法；旧的单字符串 `role` 保持兼容：

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

- `modules/<role>/.../nixos.nix` 或 `home.nix`：该角色位于主机 `roles` 时注入。
- `modules/_common/...`：始终注入，适合共享但只属于单侧的模块。
- `modules/.../default.nix`：始终注入，保证共享 option 接口可见。
- 未声明 `roles` / `role` 时，全部配置模块照旧注入。

框架在把主机模块交给 NixOS 前会剥离顶层 `roles` / `role`。角色值应是字符串列表或字符串；无法提前判定时会回退为全量注入。

### 额外模块钩子

```nix
inputs.cloud.lib.mkFlake {
  inherit inputs;
  extraNixosModules = [ ./overrides/nixos.nix ];
  extraHomeModules = [ ./overrides/home.nix ];
  extraModules = [ ./overrides/shared.nix ];
}
```

`extraHomeModules` 会同时进入独立 home-manager 与嵌入式 home-manager，不需要重复配置。

### 模块输出

`mkFlake` 暴露可供其他 flake 复用的目录级模块输出：

- `nixosModules.<目录键>`：同一模块目录中的 `default.nix` + `nixos.nix`，值为 `{ imports = [ ... ]; }`。
- `homeModules.<目录键>`：同一模块目录中的 `default.nix` + `home.nix`。

例如 `modules/desktop/hyprland/nixos.nix` 对应 `nixosModules.desktop.hyprland` 的扁平属性名 `"desktop.hyprland"`，不会暴露 magic 文件名。目录键冲突时框架会在求值期报错。

### 统一 nixpkgs 包集合

自动发现的 `overlays/<name>/default.nix`、`extraOverlays` 与 `nixpkgsConfig` 会统一应用到：

- NixOS 的 `pkgs`；
- 独立与嵌入式 home-manager 的 `pkgs`；
- `packages`、`devShells`、`checks`、`apps` 与 `formatter`。

因此自定义包可以直接依赖 overlay 新增的属性，无需再从 `nixpkgs.legacyPackages` 手动构造另一套包集合：

```nix
inputs.cloud.lib.mkFlake {
  inherit inputs;
  nixpkgsConfig = {
    allowUnfree = true;
    permittedInsecurePackages = [ "example-1.0" ];
  };
  extraOverlays = [ (final: prev: { /* ... */ }) ];
}
```

### 扩展 output 目录

除既有 packages / shells / checks 外，框架原生发现以下目录：

- `apps/<name>/default.nix` → `apps.<system>.<name>`，文件应返回标准 app attrset。
- `formatter/default.nix` → `formatter.<system>`，文件应返回 formatter derivation。
- `deploy/default.nix` → 顶层 `deploy`，可用于 deploy-rs 等部署工具的配置。

`apps` 与 `formatter` 使用统一 `pkgs.callPackage`，除包参数外还可按需声明 `inputs`、`self`、`cloud`。`deploy/default.nix` 可按需声明 `lib`、`inputs`、`self`、`cloud`。目录不存在时不会生成对应 output；其他特殊 output 仍可通过 `extraOutputs` 补充。

### 开发体验

- **格式化**：本仓库的 `nix fmt` 经顶层 `formatter` 输出调用 treefmt；用户仓库若提供 `formatter/default.nix`，则生成自己的 `formatter.<system>`。
- **选项文档**：`nix build .#options.<system> -o docs/public/options.json` 导出当前 `cloud.*` 公共选项接口。该 output 不计入 checks。

## 模块写作范式

模块采用**单树 + 文件名分拣**，一个程序只对应一个目录，消除 NixOS 与 home-manager 两棵平行树的重复：

- `default.nix`：**中性模块**，声明该程序共享的 option 接口（`options.cloud.<name>.*`），不引用 `services.*` 或 `programs.*`。
- `nixos.nix`：NixOS 专属逻辑，读取 `config.cloud.<name>.*` 挂服务。
- `home.nix`：home-manager 专属逻辑，读取同一 option 挂 dotfile。

```nix
# modules/desktop/hyprland/default.nix
{ config, lib, ... }: {
  options.cloud.hyprland = {
    enable = lib.mkEnableOption "Hyprland";
  };
}
```

```nix
# modules/desktop/hyprland/nixos.nix
{ config, ... }: {
  config = {
    # 依据 config.cloud.hyprland.enable 决定系统级配置
  };
}
```

```nix
# modules/desktop/hyprland/home.nix
{ config, ... }: {
  config = {
    # 依据相同 config.cloud.hyprland.enable 决定用户级配置
  };
}
```

模块名由相对路径去掉 magic 文件名、以 `.` 连接派生（`modules/desktop/hyprland/nixos.nix` → `desktop.hyprland`），用于错误定位与去重。category 层（`modules/<category>/<name>/`）为可选的组织方式，发现逻辑容忍任意深度。

### 主机与用户关联（自动推导）

主机与 home 的关联由目录结构推导，**无需在 host 模块里手写 `config.cloud.users`**：

- `homes/<user>/default.nix` 是用户共享 home，同时生成独立 `homeConfigurations.<user>`。
- `homes/<user>/<host>.nix` 生成独立 `homeConfigurations."<user>@<host>"`，并将用户关联到对应 NixOS 主机。
- 默认 `embedHomeManager = true` 时，关联的 home 会通过 home-manager NixOS 模块嵌入 `nixosConfigurations.<host>`。
- 设置 `embedHomeManager = false` 后，两个独立 home outputs 仍照常生成，但 NixOS 不再导入 home-manager，适合只使用 `home-manager switch` 的仓库。

```nix
# homes/rhencloud/nixos-desktop.nix
{ ... }:
{
  # 仅该主机专属的 home 配置
}
```

```nix
# flake.nix
outputs = inputs:
  inputs.cloud.lib.mkFlake {
    inherit inputs;
    embedHomeManager = false;
  };
```

`cloud.users` 由框架写入推导结果，模块可读取但不应手动赋值。

## Overlays 与打补丁

框架在 `cloud` 命名空间提供 `patches` helper，简化对 nixpkgs / flake inputs 包打补丁的样板；patch 逻辑仍写在 `overlays/<name>/default.nix`。自动发现的 overlay 不仅作为 `overlays.<name>` 暴露，也会进入 NixOS、独立/嵌入式 home-manager 以及所有 per-system outputs 使用的统一包集合：

```nix
# overlays/foo/default.nix
{ cloud }: final: prev: {
  foo = prev.foo.overrideAttrs (oa: {
    patches = (oa.patches or []) ++ [
      (cloud.patches.local ./fix.patch)          # 本地 patch
      (cloud.patches.fromPR {                    # GitHub PR patch
        inherit (prev) fetchpatch;
        owner = "NixOS";
        repo = "nixpkgs";
        pr = 123456;
        hash = "sha256-...";                     # 留 null 让 nix 报出期望 hash 后回填
      })
    ];
  });
}
```

- `cloud.patches.local path`：本地 `.patch` 文件，路径透传。
- `cloud.patches.fromPR { fetchpatch; owner; repo; pr; hash; }`：拼接 `https://github.com/<owner>/<repo>/pull/<pr>.patch` 并用 `fetchpatch` 拉取。`hash` 必须固定以保证可复现，开发期可置 `null` 触发报错回填。

多版本包需求（如锁定某个包的旧版本）不通过多 nixpkgs channel 实现，而是可选集成 [nixpkgs-multiverse](https://github.com/fzakaria/nixpkgs-multiverse)：

```nix
{ inputs, ... }: {
  imports = [ inputs.multiverse.nixosModules.default ];
  multiverse.enable = true;
  multiverse.pins.python3 = "3.8.9";
}
```

## 密钥管理（sops）

框架提供显式的 sops-nix helper，但**不会自动注入 sops-nix 模块，也不会合并两个 YAML 文件**。默认文件选择规则是二选一：

- `host = null`：`secrets/common.yaml`；
- `host = "<host>"`：`secrets/hosts/<host>.yaml`。

```nix
# flake.nix 中由用户自行声明 input
# sops-nix.url = "github:Mic92/sops-nix";
# sops-nix.inputs.nixpkgs.follows = "nixpkgs";

# hosts/nixos-desktop.x86_64-linux/default.nix
{ cloud, inputs, ... }:
{
  imports = [
    (cloud.sops.mkModule {
      sopsNixModule = inputs.sops-nix.nixosModules.sops;
      host = "nixos-desktop";
    })
  ];
}
```

可用接口：

- `cloud.sops.commonFile`；
- `cloud.sops.hostFile host`；
- `cloud.sops.defaultFile host`；
- `cloud.sops.mkModule { sopsNixModule; host ? null; defaultSopsFile ? cloud.sops.defaultFile host; }`。

需要自定义位置或自行组合密钥时，显式传入 `defaultSopsFile`。sops-nix 的 `sops.secrets` 本身也允许逐个 secret 指定 `sopsFile`。

## 常见用法

```bash
# 构建并切换主机
sudo nixos-rebuild switch --flake .#nixos-desktop

# 切换用户环境（全局 home）
home-manager switch --flake .#rhencloud

# 切换某主机专属 home
home-manager switch --flake .#rhencloud@nixos-desktop

# 构建隔离检查（CI）
nix flake check
```

## 与其他框架对比

| | Cloud Nix Framework | snowfallorg/lib | flake-fhs | flake.parts | nixos-unified | den |
| ---- | ---- | ---- | ---- | ---- | ---- | ---- |
| 定位 | 约定式配置框架 | 统一配置库 | 目录映射 outputs | 通用 flake 模块系统 | 三平台统一配置模块 | 面向切面、功能优先 |
| 组织方式 | 目录约定 + 单树分拣 | 目录约定 + 分类 | 目录树即 flake | flake 模块系统 | flake-parts 模块 + autowiring | aspect 函数 + policy |
| NixOS + home-manager | 是（同源双轨） | 是 | 是 | 可组合 | 是（+nix-darwin） | 是（+darwin + 自定义 class） |
| 运行时依赖 | 纯 nixpkgs.lib | flake-utils-plus | 自研 | 自研模块系统 | flake-parts | 零依赖（可选集成） |
| 目录自动发现 | 是 | 是 | 是 | 否 | 可选 autowiring | 否 |

- [nixos-unified](https://nixos-unified.org/)：flake-parts 模块，用统一的 `.#activate` app 一键激活/部署（含远程 SSH），统一 NixOS + nix-darwin + home-manager；可选 autowiring 扫描目录自动挂接 outputs。
- [den](https://den.denful.dev)：面向切面（aspect-oriented）、功能优先。核心抽象是 aspect —— 一个以 context（`{ host, user }`）为参数的函数，返回多个 Nix class（nixos/darwin/homeManager 等）的配置，用 policy 描述实体拓扑；零依赖，支持 flake 与非 flake。

## 参与开发

见 [AGENTS.md](./AGENTS.md)。

## 许可证

MIT
