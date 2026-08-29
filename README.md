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
├── lib/                                  # 项目级工具库
├── shells/<name>/default.nix             # devShells
├── checks/<name>/default.nix             # flake checks
└── secrets/                              # sops（common.yaml + hosts/<host>.yaml）
```

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

  outputs = inputs: inputs.cloud.mkFlake {
    inherit inputs;
  };
}
```

仅凭这一段，`hosts/`、`homes/`、`modules/`、`packages/`、`overlays/`、`lib/`、`shells/`、`checks/` 下的内容就会被自动解析成完整配置。

## 核心 API

框架通过 `lib` 输出暴露统一的命名空间 `cloud`：

### `mkFlake`

顶层 outputs 构造器，自动扫描目录并拼接出全部 outputs：

```nix
inputs.cloud.mkFlake {
  inherit inputs;                                  # 透传所有 flake inputs
  systems = [ "x86_64-linux" "aarch64-linux" ];    # 仅用于 per-system outputs（packages/checks/devShells）
  extraOutputs = { };                              # 深合并覆盖自动生成项
  extraSpecialArgs = { };                          # 追加注入模块的 specialArgs
}
```

### `mkSystem`

创建单个 `nixosConfigurations.<host>`：

```nix
cloud.mkSystem {
  host = "nixos-desktop";
  system = "x86_64-linux";     # 可为 null，从 hosts/<host>.<system>/ 派生
  modules = [ ];               # 追加到自动发现之后
  extraSpecialArgs = { };
}
```

### `mkHome`

创建单个 `homeConfigurations.<user>`：

```nix
cloud.mkHome {
  user = "rhencloud";
  host = "nixos-desktop";      # null = 全局 home；非 null = "<user>@<host>" 并继承该 host 的 system
  system = "x86_64-linux";     # 仅全局 home 使用；不填则默认取 systems 的首项（mkFlake）或 defaultSystems[0]
  modules = [ ];
  extraSpecialArgs = { };
}
```

> ⚠️ **全局 home 的构建架构**：`mkFlake` 生成全局 `homeConfigurations.<user>` 时，`system` 默认取 `systems` 列表的**首项**。若你的机器架构不是 `systems` 的首项（例如 aarch64 用户但 `systems` 以 `x86_64-linux` 开头），请**将本机架构置于 `systems` 首位**，或改用 `mkHome { system = "aarch64-linux"; }` 显式声明，否则全局 home 会以错误架构构建、激活时才暴露不匹配。

### `mkLib` / `importModules` / `flattenTree`

- `mkLib { inherit inputs; }` 返回 `cloud` 命名空间。
- `importModules` / `flattenTree` 是目录自动发现工具函数，按全局路径字典序稳定遍历。

### 注入的模块参数

所有模块（NixOS 与 home-manager，含独立 `home-manager switch` 构建）均自动获得：`inputs`（全部 flake inputs）、`channels`（单 `nixpkgs` 预留解析入口）、`self`（本 flake）、`cloud`（框架 helper：`cloud.patches` / `cloud.sops`），以及 NixOS/HM 原生参数（`config` / `pkgs` / `lib` / `options` 等）。

### 求值模型

框架对每台主机 / 每个 home 都只做**单次求值**。主机与用户的关联、要嵌入哪些 home，均通过目录结构**在求值前自动推导**，无需先求值再重建：

- **NixOS 主机**：从 `hosts/<name>.<system>/` 后缀直接得到 `system`，无需探测。
- **per-host home**（`"<user>@<host>"`）：`system` 继承对应主机的 `.<system>` 后缀。
- **全局 home**（仅 `homeConfigurations.<user>`，无 host）：`system` 由 `mkHome { system = ...; }` 显式提供；`mkFlake` 生成时默认取 `systems` 的首项。框架不再依赖已废弃的 `cloud.system` 选项（当前不提供），故无需两遍探测。

### 镜像生成

框架基于 nixpkgs 原生 `image.modules` / `system.build.images`（nixos-generators 已并入 nixpkgs，无需额外 input），按主机声明生成镜像输出。每台主机在 `hosts/<name>.<system>/default.nix` 内声明需要的变体，框架映射为 `images.<host>.<format>` flake 输出（**不计入 checks**，按需 `nix build .#images.<host>.<format>` 才真正构建）：

```nix
# hosts/nixos-desktop.x86_64-linux/default.nix
{ config, ... }: {
  config.cloud.images.formats = [ "iso" "raw" "oci" ];
}
```

可用变体即 `image.modules` 中的键（iso / raw / raw-efi / qemu / qemu-efi / oci / amazon / azure / vmware / virtualbox …），详见 `nixos-rebuild build-image` 列表。若声明的变体在当期 nixpkgs 不存在，框架在求值期抛出明确错误。`cloud.images` 选项只注入 NixOS 主机，不进入 home-manager 配置。

### 模块注册表（opt-in）

通过 `mkFlake` 的 `moduleRegistries` 参数并入外部模块源（建议 input 命名为 `cloudModules.<name>`，但不强制前缀）。每个注册表 flake 暴露 `modules` 输出，其形状与框架自动发现一致：`{ nixos = [ ... ]; home = [ ... ]; }`。本地模块优先级高于注册表（注册表模块先于本地模块求值，配置合并时本地胜出），由 `flake.lock` 锁定版本：

```nix
inputs.cloudModules.example.url = "github:org/cloud-modules";

outputs = { self, nixpkgs, cloudModules, ... }:
  cloud.mkFlake {
    inherit inputs;
    moduleRegistries = [ cloudModules ];   # opt-in，缺省为 [ ]
  };
```

 远程注册表复用与本地相同的 `groupModules` 分拣结构（`nixos` / `home` 双侧），框架自动并入 `autoModules`。

### 角色过滤（opt-in）

主机可在 `hosts/<name>.<system>/default.nix` **顶层**声明 `role = "desktop"`（**顶层字段，不在 `config` 内**；框架在把该模块交给 NixOS 前会剥离 `role`，故不会触发「未知模块属性」报错）。当主机声明 `role` 时，框架只对这台主机注入 `modules/<role>/` 下的 `nixos.nix`/`home.nix`，其余角色的 config 模块在求值期即被筛除，无需 `mkIf` 守卫兜底：

```nix
# hosts/nixos-desktop.x86_64-linux/default.nix
{ config, ... }: {
  role = "desktop";
  config = { /* ... */ };
}
```

- `modules/<role>/.../nixos.nix`（或 `home.nix`）：仅当主机 `role == <role>` 时注入。
- `modules/_common/...`（下划线前缀）：**始终注入**，是「共享但单端」模块的归属地（如通用 boot / networking 的 `nixos.nix`），无需塞进 `default.nix` 造成泄漏到 home-manager。
- `modules/.../default.nix`（option 接口）：**始终注入**，与角色无关——保证 `options.cloud.*` 全主机可见，`mkIf config.cloud.<x>.enable` 仍可用。
- 未声明 `role` 时全部 config 模块照旧全量注入，向后兼容。

角色值在求值前从主机模块的顶层 `role` 字段 best-effort 读取（函数式主机模块会以真实 pkgs 调用再读字面量）；若无法静态判定（如 `role` 被 `mkIf`/`mkMerge` 包裹），回退为全量注入。

### 额外模块钩子（extraModules / extraNixosModules / extraHomeModules）

`mkFlake` 接受三组模块列表，是对「魔术目录 + 模块注册表」的补充，便于不新建 flake、不调整目录结构就挂入外部模块：

- `extraModules`：同时追加进**每台主机与每个 home** 的最终模块列表；
- `extraNixosModules`：仅追加进 NixOS 主机；
- `extraHomeModules`：仅追加进 home-manager home。

`mkSystem` 接受 `extraModules` / `extraNixosModules`；`mkHome` 接受 `extraModules` / `extraHomeModules`。分端参数可避免把 sops-nix 这类纯 NixOS 模块误注入 home 导致报错：

```nix
cloud.mkFlake {
  inherit inputs;
  extraNixosModules = [ ./overrides/nixos.nix ];
  extraHomeModules = [ ./overrides/home.nix ];
  extraModules = [ ./overrides/shared.nix ];
}
```

### 模块输出（nixosModules / homeModules）

`mkFlake` 额外暴露两个顶层输出，供其它 flake 复用本仓库自动发现的模块：

- `nixosModules.<名>`：`modules/**` 下 NixOS 侧模块（`default.nix` + `nixos.nix`），键为相对路径点分（如 `desktop.hyprland`）。
- `homeModules.<名>`：home-manager 侧模块（`default.nix` + `home.nix`）。

模块目录若发生重名（不同路径映射到同一模块名），框架在求值期抛错，避免静默合并。

### 开发体验

- **格式化**：`nix fmt` 经 `formatter` 输出调用 treefmt，统一跑 nixfmt（Nix）与 mdformat（Markdown）。devShell 仍保留 `nix` / `statix` / `deadnix` / `nodejs` 等手工工具。
- **选项文档**：`nix build .#options.<system> -o docs/public/options.json` 导出当前 `cloud.*` 公共选项接口（仅 `options.cloud.*`，JSON 化后写入 `docs/public/options.json`）。该 `options` 输出**不计入 checks**，按需构建。

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

- `homes/<user>/default.nix` 是一个用户的共享 home（挂到所有该用户的 `<user>@<host>`，以及独立 `homeConfigurations.<user>`）。
- `homes/<user>/<host>.nix` 表示该 home **关联到某主机**，框架据此自动把 `<user>` 加入该主机的 `cloud.users`，并将其 home 内嵌进 `nixosConfigurations.<host>`。

```nix
# homes/rhencloud/nixos-desktop.nix   -> 自动让 rhencloud 关联主机 nixos-desktop
{ config, ... }: {
  # 仅该主机专属的 home 配置
}
```

`hosts/<name>.<system>/default.nix` 只需关注系统级配置，系统架构由目录后缀决定（框架不猜测默认架构）。`cloud.users` 在求值期由框架写入推导结果，模块可读取但不应手动赋值。

## Overlays 与打补丁

框架在 `cloud` 命名空间提供 `patches` helper，简化对 nixpkgs / flake inputs 包打补丁的样板；patch 逻辑仍写在 `overlays/<name>/default.nix`（就近原则，本地 patch 与 overlay 同目录）：

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

框架内置 sops-nix 集成的 helper（不硬编码 input，约定 + 助手）：自动按 `secrets/common.yaml` 与 `secrets/hosts/<host>.yaml` 组合各机的 `defaultSopsFile`，并注入 sops-nix 模块。用 `cloud.sops` 配置时，sops-nix input 由用户通过 `follows` 提供。

最小接入（在 host 模块里）：

```nix
# flake.nix inputs 中加上
# sops-nix.url = "github:Mic92/sops-nix";
# cloud.inputs.sops-nix.follows = "sops-nix";

# hosts/<name>.<system>/default.nix
{ config, cloud, inputs, ... }: {
  imports = [
    (cloud.sops.mkModule { sopsNixModule = inputs.sops-nix.nixosModules.sops; })
  ];

  # 之后即可声明 sops.secrets.<name>.path 等
  sops.secrets.example.path = ./secrets/common.yaml;
}
```

`cloud.sops.mkModule { sopsNixModule; host?; }`：`host` 为空时 `defaultSopsFile` 指向 `secrets/common.yaml`，否则指向 `secrets/hosts/<host>.yaml`；`sopsNixModule` 需由调用方传入（框架不绑定具体 input）。

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
