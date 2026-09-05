# Snowveil

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
| Patch helper | `lib/patches.nix` | `snowveil.patches.local` / `fromPR` | 完成 |
| Flake 入口 | `flake.nix` | 暴露 `lib` / `templates` / `checks` | 完成 |
| 模板 | `templates/default/` | `nix flake init --template` | 完成 |
| 示例 | `examples/` | 可运行的最小示例 | 完成 |
| 自检 | `checks/` | `nix flake check` | 完成 |
| 文档 | `README.md` / `AGENTS.md` | 项目说明与开发约定 | 完成 |

## 快速开始

### 1. 初始化模板

```bash
nix flake init --template github:SnowveilOrg/Snowveil
```

### 2. 目录结构

一个标准的用户配置仓库长这样：

```text
.
├── flake.nix
├── hosts/
│   └── nixos-desktop/
│       ├── meta.nix                      # 角色、profile、框架元数据（必须声明 system）
│       ├── default.nix                   # nixosConfigurations.nixos-desktop
│       ├── hardware.nix                  # 可选：硬件配置，存在则自动 import
│       ├── disk.nix                      # 可选：磁盘布局（disko / fileSystems）
│       └── network.nix                   # 可选：网络配置，存在则自动 import
├── profiles/
│   ├── workstation.nix                   # Profile：命名的模块启用包
│   └── personal.nix
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
│   └── <system>/<name>/default.nix       # 明确的单架构 package
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

| 目录 | 生成的 output |
| ---- | ------------- |
| `hosts/<name>/default.nix` | `nixosConfigurations.<name>` |
| `hosts/<name>/{hardware,disk,network}.nix` | 可选：主机目录 magic 文件，存在则按固定顺序随主机自动 import |
| `hosts/<name>/meta.nix` | 角色与主机级 Home Manager 策略（需声明 `system`） |
| `users/<name>/meta.nix` | 声明用户属性，自动生成 `users.users.<name>` / `users.groups.<name>` |
| `users/<name>/default.nix` | 可选：`users.users.<name>` 补充模块 |
| `homes/<user>/default.nix` | `homeConfigurations.<user>` |
| `homes/<user>/<host>.nix` | `homeConfigurations."<user>@<host>"` |
| `modules/**/{default,nixos,home}.nix` | 自动注入，并生成 `nixosModules.<目录键>` / `homeModules.<目录键>` |
| `packages/<name>/default.nix` | `packages.<system>.<name>` |
| `packages/<system>/<name>/default.nix` | 单架构 `packages.<system>.<name>` |
| `packages/<name>.<system>/default.nix` | 旧式单架构约定，继续兼容 |
| `overlays/<name>/default.nix` | `overlays.<name>`，并自动应用到框架创建的全部包集合 |
| `apps/<name>/default.nix` | `apps.<system>.<name>` |
| `formatter/default.nix` | `formatter.<system>` |
| `deploy/default.nix` | `deploy` |
| `lib/*.nix` | `lib.<name>` |
| `shells/<name>/default.nix` | `devShells.<system>.<name>` |
| `checks/<name>/default.nix` | `checks.<system>.<name>` |

> `hosts/` 下的主机目录使用裸名称，`meta.nix` **必须声明 `system`**；目录内可选识别 `hardware.nix` / `disk.nix` / `network.nix`，存在则按固定顺序自动 import。package/check/app/shell 可添加 `meta.nix`，通过 `enable` 与 `systems` 控制自动发现。

### 3. flake.nix 最小示例

```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    home-manager.url = "github:nix-community/home-manager";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";
    snowveil.url = "github:SnowveilOrg/Snowveil";
    snowveil.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = inputs: inputs.snowveil.lib.mkFlake {
    inherit inputs;
  };
}
```

仅凭这一段，`hosts/`、`homes/`、`modules/`、`packages/`、`overlays/`、`apps/`、`formatter/`、`deploy/`、`lib/`、`shells/`、`checks/` 下的内容就会被自动解析成完整配置。

## 核心 API

框架通过 flake 的 `lib` 输出暴露统一命名空间。用户 flake 中应从 `inputs.snowveil.lib` 调用，完整入口是 `inputs.snowveil.lib.mkFlake`。

### `mkFlake`

顶层 outputs 构造器，自动扫描目录并拼接全部 outputs。0.3.0 起推荐按职责使用嵌套命名空间：

```nix
inputs.snowveil.lib.mkFlake {
  inherit inputs;
  root = ./.;
  systems = [ "x86_64-linux" "aarch64-linux" ];

  nixpkgs = {
    config = { allowUnfree = true; };
    overlays = [ ];
  };

  nixos = {
    modules = [ ];
    specialArgs = { };
  };

  home = {
    modules = [ ];
    specialArgs = { };
    embed = true;
    useGlobalPkgs = true;
  };

  outputs = {
    extra = { };
    disabled = [ ];
    expected = { };
    eval = {
      hosts = false;
      homes = false;
    };
    diagnostics = {
      discovery = true;
      moduleGraph = true;
      perHostModuleGraph = false;
      doctor = true;
      expectedScaffold = true;
    };
  };

  moduleRegistries = [ ];
  moduleGroups = { };
}
```

- `root`：配置仓库根目录，通常从调用位置自动推导。
- `systems`：生成 per-system outputs 的架构列表。
- `nixpkgs.config` / `nixpkgs.overlays`：统一配置所有 nixpkgs 实例。
- `nixos.modules` / `nixos.specialArgs`：仅注入 NixOS。
- `home.modules` / `home.specialArgs`：注入独立与嵌入式 Home Manager。
- `home.embed`：控制是否嵌入关联 home，支持 bool、`host: bool` 和 per-host 属性集。
- `home.useGlobalPkgs`：控制嵌入式 HM 是否复用 NixOS `pkgs`，同样支持按主机配置。
- `outputs.extra`：与自动生成 outputs 深度合并。
- `outputs.disabled`：在求值文件前禁用指定 package、check、app、shell、formatter 或 deploy。
- `outputs.expected`：校验框架生成的 output 集合，支持 `subset` / `exact` 及 hosts、homes、packages、apps、checks、devShells、overlays、modules、formatter、deploy、images。
- `outputs.eval`：按需生成 NixOS / Home Manager 聚合求值检查；字段可为 bool 或目标名称列表，默认关闭。
- `outputs.diagnostics`：控制 discovery JSON、DOT 模块图、per-host 模块图、`snowveil-doctor` 健康检查及 `outputs.expected` scaffold；per-host 图默认关闭，其余默认启用。
- `moduleRegistries`：按需并入外部模块注册表。
- `moduleGroups`：注册 all-of 模块组，供模块 metadata 的 `requiresGroups` 使用。

```nix
home.embed = {
  default = true;
  hosts.yc-hk-1 = false;
};

home.useGlobalPkgs = host: host != "nixos-desktop";
```

主机 `meta.nix` 中的 `home.embed` / `home.useGlobalPkgs` 优先于全局策略。旧的扁平 `mkFlake` 参数仍兼容，但会输出弃用 trace；迁移表见[版本策略](./docs/reference/versioning.md)。

### `mkSystem`

`mkSystem` / `mkHome` 需要先通过 `mkLib { inherit inputs; }` 绑定当前用户 flake；它们不是框架 input 上的未绑定函数。

创建单个 `nixosConfigurations.<host>`：

```nix
outputs = inputs:
  let
    snowveil = inputs.snowveil.lib.mkLib { inherit inputs; };
  in
  {
    nixosConfigurations.nixos-desktop = snowveil.mkSystem {
      host = "nixos-desktop";
      system = "x86_64-linux"; # 必须声明在 hosts/<host>/meta.nix
      modules = [ ];
      extraModules = [ ];
      extraNixosModules = [ ];
      extraHomeModules = [ ];
      extraSpecialArgs = { };
      nixpkgsConfig = { };
      extraOverlays = [ ];
      embedHomeManager = true;
      homeManagerUseGlobalPkgs = true;
    };
  };
```

### `mkHome`

创建单个 `homeConfigurations.<user>` 或 `homeConfigurations."<user>@<host>"`：

```nix
outputs = inputs:
  let
    snowveil = inputs.snowveil.lib.mkLib { inherit inputs; };
  in
  {
    homeConfigurations."rhencloud@nixos-desktop" = snowveil.mkHome {
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

### `mkLib` / 版本 / 自动发现函数 / patch 与 sops helper

- `mkLib { inherit inputs; }` 返回已绑定当前 flake 的 `snowveil` 命名空间。
- `version` 返回 `{ major; minor; patch; pre; string; }`，当前为 `0.5.0-dev`；完整策略见[版本策略](./docs/reference/versioning.md)。
- `importModules` / `flattenTree` / `groupModules` 是目录自动发现工具函数；`groupModules` 还返回模块 `meta`，自动组合采用字典序兜底的稳定拓扑排序。
- `snowveil.patches.local` / `snowveil.patches.fromPR` 提供 patch helper。
- `snowveil.sops.commonFile` / `hostFile` / `defaultFile` / `secret` / `mkModule` 提供显式的 sops-nix 接入助手。
- `snowveil.source.clean { root?; excludes?; }` 提供统一源码过滤；绑定命名空间还提供 `snowveil.projectSource`。

### 注入的模块参数

所有模块（NixOS、独立 home-manager 与嵌入式 home-manager）均自动获得：`inputs`、`channels`、`self`、`snowveil`，以及对应模块系统的原生参数。`nixos.specialArgs` 与 `home.specialArgs` 分别注入对应模块系统；旧的 `extraSpecialArgs` 仍作为两侧共同参数兼容。

### 求值模型

推荐在 `hosts/<name>/meta.nix` 保存角色与框架策略。该文件是静态属性集，**必须声明 `system` 字段**；框架无需预执行函数式 host module，`default.nix` 只交给 NixOS module system 正式求值，因此可在外层使用真实 `config`。主机目录还支持可选的 `hardware.nix` / `disk.nix` / `network.nix`，存在则按此固定顺序随 `default.nix` 自动 import（见[多主机管理](./docs/guide/multiple-hosts.md)）。

```nix
# hosts/nixos-desktop/meta.nix
{
  roles = [ "desktop" "development" ];
  home.useGlobalPkgs = false;
}
```

旧的 host module 顶层 `role` / `roles` 等元数据继续兼容，但需要一次占位参数探测。探测失败时框架会发出迁移警告、回退为全量角色注入，并让主机级 Home Manager 策略继续使用全局值；新配置不应依赖该兼容路径。

主机与用户关联仍在正式模块求值前由目录结构推导：

- **NixOS 主机**：从 `hosts/<name>/meta.nix` 中的 `system` 字段获取系统架构。
- **per-host home**：`"<user>@<host>"` 继承对应主机架构。
- **全局 home**：由 `mkHome.system` 指定；`mkFlake` 默认使用 `systems` 首项。

### 镜像生成

框架基于 nixpkgs 原生 `image.modules` / `system.build.images`，按主机声明生成 `images.<host>.<format>`，不计入 checks：

```nix
# hosts/nixos-desktop/meta.nix
{
  system = "x86_64-linux";
  images.formats = [ "iso" "raw" "oci" ];
}
```

若声明的变体在当前 nixpkgs 不存在，框架会在求值期抛出明确错误。

### 模块注册表（opt-in）

`moduleRegistries` 可并入外部模块源。注册表 flake 应暴露 `{ modules = { nixos = [ ... ]; home = [ ... ]; }; }`；注册表模块先于本地模块进入列表：

```nix
outputs = inputs:
  inputs.snowveil.lib.mkFlake {
    inherit inputs;
    moduleRegistries = [ inputs.snowveilModules.example ];
  };
```

### 组合角色过滤（opt-in）

推荐在主机静态元数据中声明角色：

```nix
# hosts/nixos-desktop/meta.nix
{
  roles = [
    "desktop"
    "development"
  ];
}
```

- `modules/<role>/.../nixos.nix` 或 `home.nix`：该角色位于主机 `roles` 时注入。
- `modules/_common/...`：始终注入。
- `modules/.../default.nix`：始终注入，保证共享 option 接口可见。
- 未声明 `roles` / `role` 时，全部配置模块照旧注入。

旧的 host module 顶层 `role` / `roles` 保持兼容，但会触发旧式元数据探测。若函数式 host module 在外层使用真实 `config`，应迁移到 `meta.nix`，避免探测失败后关闭角色过滤。

### 额外模块钩子

```nix
inputs.snowveil.lib.mkFlake {
  inherit inputs;
  nixos.modules = [
    ./overrides/shared.nix
    ./overrides/nixos.nix
  ];
  home.modules = [
    ./overrides/shared.nix
    ./overrides/home.nix
  ];
}
```

`home.modules` 会同时进入独立与嵌入式 Home Manager。需要两侧共享的模块应显式加入两个列表，使注入边界保持清晰。

### 模块输出

`mkFlake` 暴露可供其他 flake 复用的目录级模块输出：

- `nixosModules.<目录键>`：同一模块目录中的 `default.nix` + `nixos.nix`，值为 `{ imports = [ ... ]; }`。
- `homeModules.<目录键>`：同一模块目录中的 `default.nix` + `home.nix`。

例如 `modules/desktop/hyprland/nixos.nix` 对应 `nixosModules.desktop.hyprland` 的扁平属性名 `"desktop.hyprland"`，不会暴露 magic 文件名。目录键冲突时框架会在求值期报错。

### 统一 nixpkgs 包集合

自动发现的 `overlays/<name>/default.nix`、`nixpkgs.overlays` 与 `nixpkgs.config` 会统一应用到：

- NixOS 的 `pkgs`；
- 独立与嵌入式 home-manager 的 `pkgs`；
- `packages`、`devShells`、`checks`、`apps` 与 `formatter`。

嵌入式 HM 默认使用 `home-manager.useGlobalPkgs = true`。对于 Stylix 等会在 HM 侧设置 overlay 的模块，可按主机设置 `home.useGlobalPkgs = false`；框架会把基础 nixpkgs 配置与 overlays 注入 HM 自己的 nixpkgs。

因此自定义包可以直接依赖 overlay 新增的属性，无需再从 `nixpkgs.legacyPackages` 手动构造另一套包集合：

```nix
inputs.snowveil.lib.mkFlake {
  inherit inputs;
  nixpkgs = {
    config = {
      allowUnfree = true;
      permittedInsecurePackages = [ "example-1.0" ];
    };
    overlays = [ (final: prev: { /* ... */ }) ];
  };
}
```

### 扩展 output 目录

除既有 packages / shells / checks 外，框架原生发现以下目录：

- `apps/<name>/default.nix` → `apps.<system>.<name>`，文件应返回标准 app attrset。
- `formatter/default.nix` → `formatter.<system>`，文件应返回 formatter derivation。
- `deploy/default.nix` → 顶层 `deploy`，可用于 deploy-rs 等部署工具的配置。

`apps` 与 `formatter` 使用统一 `pkgs.callPackage`，除包参数外还可按需声明 `inputs`、`self`、`snowveil`。`deploy/default.nix` 可按需声明 `lib`、`inputs`、`self`、`snowveil`。目录不存在时不会生成对应 output；其他特殊 output 仍可通过 `outputs.extra` 补充。

自动发现条目可通过 `outputs.disabled` 或同目录 `meta.nix` 的 `enable` / `systems` 禁用。单架构 package 推荐使用 `packages/<system>/<name>/default.nix`，旧的 `<name>.<system>` 后缀在 package 中继续兼容。hosts 目录已改为 `hosts/<name>/` 格式，system 需在 `meta.nix` 中声明。

### 开发体验

- **格式化**：本仓库的 `nix fmt` 经顶层 `formatter` 输出调用 treefmt；用户仓库若提供 `formatter/default.nix`，则生成自己的 `formatter.<system>`。
- **选项文档**：`nix build .#options.<system> -o docs/public/options.json` 导出当前 `snowveil.*` 公共选项接口。该 output 不计入 checks。

## 模块写作范式

模块采用**单树 + 文件名分拣**，一个程序只对应一个目录，消除 NixOS 与 home-manager 两棵平行树的重复：

- `default.nix`：**中性模块**，声明该程序共享的 option 接口（`options.snowveil.<name>.*`），不引用 `services.*` 或 `programs.*`。
- `nixos.nix`：NixOS 专属逻辑，读取 `config.snowveil.<name>.*` 挂服务。
- `home.nix`：home-manager 专属逻辑，读取同一 option 挂 dotfile。

```nix
# modules/desktop/hyprland/default.nix
{ config, lib, ... }: {
  options.snowveil.hyprland = {
    enable = lib.mkEnableOption "Hyprland";
  };
}
```

```nix
# modules/desktop/hyprland/nixos.nix
{ config, ... }: {
  config = {
    # 依据 config.snowveil.hyprland.enable 决定系统级配置
  };
}
```

```nix
# modules/desktop/hyprland/home.nix
{ config, ... }: {
  config = {
    # 依据相同 config.snowveil.hyprland.enable 决定用户级配置
  };
}
```

模块名由相对路径去掉 magic 文件名、以 `.` 连接派生（`modules/desktop/hyprland/nixos.nix` → `desktop.hyprland`），用于错误定位与去重。category 层（`modules/<category>/<name>/`）为可选的组织方式，发现逻辑容忍任意深度。

### 用户（一等实体）与主机关联

用户由 `users/<name>/` 目录声明，是框架的一等实体，不再是 `homes/<user>/<host>.nix` 的推导结果。`users/<name>/meta.nix` 是用户与主机关联的**唯一来源**：

```nix
# users/rhencloud/meta.nix
{
  hosts = [ "nixos-desktop" "hm-standalone" ];  # 此用户关联的主机（必需）
  uid = 1000;
  extraGroups = [ "wheel" ];
  hashedPasswordSecret = "rhencloud-password";  # sops 密钥名，或 "/字面/路径"
}
```

框架在对应主机自动生成 `users.users.<name>` 与 `users.groups.<name>`（`isNormalUser`、`home`、`createHome`、`group`、`uid`、`extraGroups`、`description`、`hashedPasswordFile`），默认值均用 `mkDefault` 包裹，可被 `users/<name>/default.nix` 或主机模块覆盖：

- `hashedPasswordSecret` 以 `/` 开头 → 视为字面文件路径，直接作为 `hashedPasswordFile`。
- 否则 → sops 密钥名，`hashedPasswordFile` 指向 `config.sops.secrets.<name>.path`，并自动声明 `sops.secrets.<name>`（来源主机文件）。
- `users/<name>/default.nix` 是补充模块（可选），在其中覆写自动生成的字段或追加 `users.users.<name>` 其他属性。

home 配置仍在 `homes/`：

- `homes/<user>/default.nix` 是共享 home，同时生成 `homeConfigurations.<user>`。
- `homes/<user>/<host>.nix` 生成 `homeConfigurations."<user>@<host>"`，把用户的 home 配置关联到对应主机。
- 默认嵌入关联 home；关闭嵌入只影响 NixOS，独立 home output 仍然保留。

每台主机可以单独配置：

```nix
# hosts/yc-hk-1/meta.nix
{
  roles = [ "server" ];
  home.embed = false;
}
```

也可从 flake 统一定义策略：

```nix
home.embed = {
  default = true;
  hosts.yc-hk-1 = false;
};
```

`home.useGlobalPkgs` 支持相同的 bool、函数和 per-host 属性集形式。`snowveil.users` 由框架根据 `users/<name>/meta.nix` 的 `hosts` 写入，模块可读取但不应手动赋值。

## Overlays 与打补丁

框架在 `snowveil` 命名空间提供 `patches` helper，简化对 nixpkgs / flake inputs 包打补丁的样板；patch 逻辑仍写在 `overlays/<name>/default.nix`。自动发现的 overlay 不仅作为 `overlays.<name>` 暴露，也会进入 NixOS、独立/嵌入式 home-manager 以及所有 per-system outputs 使用的统一包集合：

```nix
# overlays/foo/default.nix
{ snowveil }: final: prev: {
  foo = prev.foo.overrideAttrs (oa: {
    patches = (oa.patches or []) ++ [
      (snowveil.patches.local ./fix.patch)          # 本地 patch
      (snowveil.patches.fromPR {                    # GitHub PR patch
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

- `snowveil.patches.local path`：本地 `.patch` 文件，路径透传。
- `snowveil.patches.fromPR { fetchpatch; owner; repo; pr; hash; }`：拼接 `https://github.com/<owner>/<repo>/pull/<pr>.patch` 并用 `fetchpatch` 拉取。`hash` 必须固定以保证可复现，开发期可置 `null` 触发报错回填。

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

# hosts/nixos-desktop/default.nix
{ snowveil, inputs, ... }:
{
  imports = [
    (snowveil.sops.mkModule {
      sopsNixModule = inputs.sops-nix.nixosModules.sops;
      host = "nixos-desktop";
    })
  ];
}
```

可用接口：

- `snowveil.sops.commonFile`；
- `snowveil.sops.hostFile host`；
- `snowveil.sops.defaultFile host`；
- `snowveil.sops.secret { source = "common" | "host"; host ? null; config ? null; name ? null; }`；
- `snowveil.sops.mkModule { sopsNixModule; host ? null; defaultSopsFile ? snowveil.sops.defaultFile host; }`。

传入 `name` 时，helper 直接返回可导入的模块片段：

```nix
imports = [
  (snowveil.sops.secret {
    source = "common";
    name = "password-hash";
  })
  (snowveil.sops.secret {
    source = "host";
    host = "nixos-desktop";
    name = "mihomo-proxies";
  })
];
```

省略 `name` 时返回单个 secret 的 option 属性集，也可直接赋值：

```nix
sops.secrets.password-hash = snowveil.sops.secret { source = "common"; };
```

`secret` 只减少路径样板，不会合并 YAML。需要自定义位置时显式传入 `defaultSopsFile` 或逐个设置 `sopsFile`。

## 常见用法

```bash
# 构建并切换主机
sudo nixos-rebuild switch --flake .#nixos-desktop

# 切换用户环境（全局 home）
home-manager switch --flake .#rhencloud

# 切换某主机专属 home
home-manager switch --flake .#rhencloud@nixos-desktop

# 构建隔离检查（CI）
nix flake check path:. --show-trace
```

框架默认生成 `checks.<system>.snowveil-discovery` JSON 报告、`snowveil-module-graph-dot` 图输出、`snowveil-doctor` 健康检查和 `snowveil-expected-scaffold`。最后一项包含可直接粘贴的完整 `outputs.expected` 精确模式配置。可通过 `outputs.eval` 启用 `snowveil-eval-hosts` / `snowveil-eval-homes`，通过 `outputs.diagnostics` 关闭不需要的诊断。所有 `snowveil-*` check 名称由框架保留。

`mkFlake` 在同一次调用内按 system 复用同一个 `pkgs`，并缓存发现索引、主机模块选择和依赖解析结果。测量无 eval cache 的性能时可运行：

```bash
RUNS=3 ./scripts/benchmark-eval.sh path:. checks.x86_64-linux.newfeatures.drvPath
```

`deploy`、`homeModules`、`images`、`options` 等自定义 output 在部分 Nix 版本中可能产生 `unknown flake output` 警告；这是原生 Nix 提示，不等同于 check 失败。

## 与其他框架对比

| | Snowveil | snowfallorg/lib | flake-fhs | flake.parts | nixos-unified | den |
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

### 细粒度模块控制

从 0.4.0 起，可在 `hosts/<name>/meta.nix` 中通过 `modules` 字段禁用特定模块：

```nix
# hosts/laptop/meta.nix
{
  system = "x86_64-linux";
  roles = [ "desktop" ];
  
  modules = {
    "desktop.gaming" = false;        # 禁用游戏配置
    "development.cuda" = false;      # 禁用 CUDA 支持
  };
}
```

模块名称对应目录结构（用点号分隔）。设置为 `false` 禁用模块，`true` 显式启用（无需通常设置）。

详见 [细粒度模块控制指南](./docs/guide/module-overrides.md)。

模块目录还可通过 `meta.nix` 声明 `requires`、`after`、`before`、`wants` 与 `conflicts`；详见 [模块依赖系统](./docs/guide/module-dependencies.md)。
