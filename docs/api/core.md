# 核心 API

框架通过 flake 的 `lib` output 暴露统一命名空间。用户 flake 中的完整入口是 `inputs.snowveil.lib.mkFlake`。

## `mkFlake`

顶层 outputs 构造器，自动扫描目录并拼接全部 outputs：

**推荐写法（嵌套命名空间，0.3.0+）**：

```nix
inputs.snowveil.lib.mkFlake {
  inherit inputs;

  # 可选；通常自动推导
  root = ./.;
  systems = [ "x86_64-linux" "aarch64-linux" ];

  nixpkgs = {
    config = { allowUnfree = true; };
    overlays = [ ];
  };

  nixos = {
    modules = [ ];       # 仅 NixOS
    specialArgs = { };
  };

  home = {
    modules = [ ];       # 仅 HM
    embed = true;        # 是否嵌入 NixOS，支持全局值、函数、per-host 属性集
    useGlobalPkgs = true;
  };

  outputs = {
    extra = { };         # 附加 outputs
    disabled = [ ];      # 禁用指定 output
    expected = { };      # 期望发现的 output（校验用）
    homes = {
      standalone = true;  # 是否为独立 HM 应用程序生成独立配置; false 仅保留 per-host 配置
    };
    eval = {
      hosts = false;
      homes = false;
    };
    diagnostics = {
      discovery = true;
      moduleGraph = true;
      perHostModuleGraph = true;
    };
  };

  moduleRegistries = [ ];
  moduleGroups = { };
}
```

| 参数 | 类型 | 默认值 | 说明 |
| ---- | ---- | ------ | ---- |
| `inputs` | attrset | 必填 | 当前用户 flake 的全部 inputs |
| `root` | path | 自动推导 | 配置仓库根目录 |
| `systems` | `[string]` | `["x86_64-linux","aarch64-linux"]` | per-system outputs 的目标架构 |
| `nixpkgs.config` | attrset | `{}` | 统一 nixpkgs 配置，如 `allowUnfree` |
| `nixpkgs.overlays` | `[overlay]` | `[]` | 在自动发现 overlays 之后追加 |
| `nixos.modules` | `[module]` | `[]` | 仅追加到 NixOS |
| `nixos.specialArgs` | attrset | `{}` | 注入 NixOS specialArgs |
| `home.modules` | `[module]` | `[]` | 追加到独立与嵌入式 HM |
| `home.specialArgs` | attrset | `{}` | 注入 HM specialArgs |
| `home.embed` | bool/fn/attrset | `true` | 是否将关联 home 嵌入 NixOS |
| `home.useGlobalPkgs` | bool/fn/attrset | `true` | 嵌入式 HM 是否复用 NixOS pkgs |
| `outputs.extra` | attrset | `{}` | 与自动生成 outputs 深度合并 |
| `outputs.disabled` | `[string]` | `[]` | 禁用自动发现的 output |
| `outputs.expected` | attrset | `{}` | 校验框架发现或生成的 output 集合，支持 `subset` / `exact` |
| `outputs.eval` | attrset | `{ hosts = false; homes = false; }` | 按 bool 或目标名称列表启用 NixOS / Home Manager 轻量求值检查 |
| `outputs.diagnostics` | attrset | 全部 `true` | 控制 discovery JSON、全局 DOT 和 per-host 模块图 |
| `moduleRegistries` | `[registry]` | `[]` | 按需并入外部模块注册表 |
| `moduleGroups` | attrset | `{}` | 注册供 `requiresGroups` 使用的显式 all-of 模块组 |

::: details 旧写法（已弃用，仍兼容）

使用旧扁平参数时会输出 `builtins.trace` 警告，但不会报错。建议迁移到嵌套命名空间。

```nix
inputs.snowveil.lib.mkFlake {
  inherit inputs;
  nixpkgsConfig = { allowUnfree = true; };  # → nixpkgs.config
  extraOverlays = [ ];                       # → nixpkgs.overlays
  extraModules = [ ];                        # → 同时加入 nixos.modules 与 home.modules
  extraNixosModules = [ ];                   # → nixos.modules
  extraHomeModules = [ ];                    # → home.modules
  extraSpecialArgs = { };                    # → nixos.specialArgs / home.specialArgs
  embedHomeManager = true;                   # → home.embed
  homeManagerUseGlobalPkgs = true;           # → home.useGlobalPkgs
  extraOutputs = { };                        # → outputs.extra
  disabledOutputs = [ ];                     # → outputs.disabled
  expectedOutputs = { };                     # → outputs.expected
}
```

`outputs.eval`、`outputs.diagnostics` 与 `moduleGroups` 没有旧式扁平别名。

:::

`home.embed` 与 `home.useGlobalPkgs` 都支持三种形式。以 `home.embed` 为例：

```nix
# 全局值
home.embed = false;

# 函数
home.embed = host: host != "yc-hk-1";

# 带默认值的 per-host 策略
home.embed = {
  default = true;
  hosts.yc-hk-1 = false;
};
```

`home.useGlobalPkgs` 同理。

主机 `meta.nix` 可以覆盖全局策略（meta.nix 中请使用 `home.embed`/`home.useGlobalPkgs`）：

```nix
# hosts/yc-hk-1.x86_64-linux/meta.nix
{
  roles = [ "server" ];
  home.embed = false;
  home.useGlobalPkgs = false;
}
```

主机元数据优先于全局策略。关闭 `home.useGlobalPkgs` 时，框架会把自动发现的 overlays、`nixpkgs.overlays` 与 `nixpkgs.config` 注入该主机的 HM nixpkgs，使 HM 模块仍可追加自己的 overlays。这适合 Stylix 等需要在 HM 侧设置 overlay 的模块。

`outputs.disabled` 推荐使用完整 output 标识：

```nix
outputs.disabled = [
  "checks.expensive"
  "checks.aarch64-linux.broken-on-aarch64"
  "packages.some-package"
  "apps.debug"
  "formatter"
  "deploy"
];
```

也可写成分类属性集：

```nix
outputs.disabled = {
  checks = [ "expensive" ];
  packages = [ "some-package" ];
};
```

`outputs.homes.standalone` 控制是否生成独立 home-manager 配置（用户级别，不关联特定主机）：

```nix
# 默认：true（向后兼容）— 同时生成 user 与 user@host
outputs.homes.standalone = true;  # homeConfigurations = { user = ...; user@host = ...; }

# 禁用：false — 仅生成 user@host（适合只使用嵌入式 HM 的项目）
outputs.homes.standalone = false; # homeConfigurations = { user@host = ...; }
```

用途：
- 减少 `nix flake show` 的输出噪音（仅嵌入式 HM 的项目）
- 加速评估（省去独立 HM 配置的编译）
- 对已有配置无影响（嵌入式 HM 独立生成）

## `mkSystem`

`mkSystem` / `mkHome` 需要先通过 `mkLib { inherit inputs; }` 绑定当前用户 flake；它们不是框架 input 上的未绑定函数。

```nix
outputs = inputs:
  let
    snowveil = inputs.snowveil.lib.mkLib { inherit inputs; };
  in
  {
    nixosConfigurations.nixos-desktop = snowveil.mkSystem {
      host = "nixos-desktop";
      system = "x86_64-linux";
      modules = [ ];
      extraNixosModules = [ ];
      extraHomeModules = [ ];
      extraSpecialArgs = { };      # NixOS specialArgs
      extraHomeSpecialArgs = { };  # 嵌入式 HM extraSpecialArgs
      nixpkgsConfig = { };
      extraOverlays = [ ];
      embedHomeManager = true;
      homeManagerUseGlobalPkgs = true;
    };
  };
```

`extraHomeModules` 与 `extraHomeSpecialArgs` 仅在嵌入关联 home 时使用。关闭嵌入不影响独立 `homeConfigurations` 的生成。`mkSystem` / `mkHome` 保留直接构造 API 的扁平参数；嵌套命名空间目前仅属于 `mkFlake`。

## `mkHome`

创建单个 `homeConfigurations.<user>` 或 `homeConfigurations."<user>@<host>"`：

```nix
outputs = inputs:
  let
    snowveil = inputs.snowveil.lib.mkLib { inherit inputs; };
  in
  {
    homeConfigurations."rhencloud@nixos-desktop" = snowveil.mkHome {
      user = "rhencloud";
      host = "nixos-desktop";
      system = "x86_64-linux"; # 仅全局 home 使用
      modules = [ ];
      extraHomeModules = [ ];
      extraSpecialArgs = { };
      nixpkgsConfig = { };
      extraOverlays = [ ];
    };
  };
```

带 `host` 的 home 自动继承对应主机目录后缀中的架构。`mkFlake` 生成全局 home 时使用 `systems` 首项。

## `mkLib`

```nix
inputs.snowveil.lib.mkLib { inherit inputs; }
```

返回已绑定当前 flake 的 `snowveil` 命名空间。

## `version`

```nix
inputs.snowveil.lib.version
# → { major = 0; minor = 5; patch = 0; pre = "dev"; string = "0.5.0-dev"; }
```

版本号也可从模块内的 `snowveil` 参数读取（`snowveil.version`）。适合在用户模块中做 feature detection 或记录依赖版本。详见[版本策略](/reference/versioning)。

## 自动发现函数

- `importModules dir`：返回扁平的 `{ nixos = [ ... ]; home = [ ... ]; }`。
- `groupModules dir`：返回 `{ nixos; home; meta; }`；两侧按目录键分组，`meta` 保存每个模块目录的依赖元数据与来源路径。
- `flattenTree tree`：将嵌套属性集展开为点分键。

无依赖约束时遍历结果按完整相对路径字典序排序；自动组合阶段会执行稳定拓扑排序。

## Patch helper

- `snowveil.patches.local path`
- `snowveil.patches.fromCommit { fetchpatch; owner; repo; rev; hash; }` — 固定到具体 commit，可复现；**推荐**
- `snowveil.patches.fromPR { fetchpatch; owner; repo; pr; hash; }` — **已弃用**，PR 再次推送后 hash 改变；请改用 `fromCommit`

## SOPS helper

- `snowveil.sops.commonFile`
- `snowveil.sops.hostFile host`
- `snowveil.sops.defaultFile host`
- `snowveil.sops.secret { source = "common" | "host"; host ? null; config ? null; name ? null; }`
- `snowveil.sops.mkModule { sopsNixModule; host ? null; defaultSopsFile ? snowveil.sops.defaultFile host; }`

`secret` 在 common、显式 `host` 或显式 `config` 模式下，传入 `name` 会返回 `{ sops.secrets.<name>.sopsFile = ...; }` 模块片段；省略 `name` 会返回 `{ sopsFile = ...; }`，便于直接赋给已有 secret。省略 `host` 和 `config` 的动态 host 模式始终返回 NixOS module。`sops` helper 不会自动注入模块，也不会合并 common 与 host 文件。

传入 `config` 时从 `config.networking.hostName` 推导 host 并返回普通属性集；同时传入 `host` 和 `config` 会报错。

## Source helper

```nix
snowveil.source.clean {
  root = ./.;
  excludes = [ "secrets" "wallpapers" ];
}

snowveil.projectSource
```

未绑定的 `inputs.snowveil.lib.source.clean` 要求传入 `root`。由 `mkLib`、模块参数和 output 文件获得的绑定 `snowveil` 默认使用项目根；`projectSource` 使用默认排除项 `.git`、`.direnv`、`.cnh` 和根级 `result`。

## Output 验证与求值

`outputs.expected.mode` 支持 `subset`（默认）和 `exact`。支持 hosts、homes、packages、apps、checks、devShells、overlays、nixosModules、homeModules、formatter、deploy 和 images；完整 schema 见[自定义 Outputs](/advanced/custom-outputs)。

`outputs.eval.hosts` / `outputs.eval.homes` 默认关闭。值为 `true` 时检查全部目标，值为字符串列表时只求值指定 host 或 home；框架按 system 生成聚合检查。`outputs.diagnostics` 默认全部开启，可关闭不需要的 discovery 或模块图，避免 CI 强制无关报告。

## 模块组与能力

`mkFlake.moduleGroups` 注册显式 all-of 组。模块 `meta.nix` 可使用 `requiresGroups`、`provides`、`requiresCapabilities`，并可在 `nixos` / `home` 下追加分侧声明。

## 分层入口

`mkFlake` 覆盖常规场景，`mkSystem` / `mkHome` 作为细粒度逃生舱。新配置应在 `hosts/<name>/meta.nix` 声明角色和 Home Manager 策略（`system` 必填）；主机目录可选识别 `hardware.nix` / `disk.nix` / `network.nix`，存在则随 `default.nix` 按固定顺序自动 import。旧的 host module 顶层 `role` / `roles` 等元数据仍兼容。
