# 版本策略

Cloud Nix Framework 采用 [Semantic Versioning 2.0.0](https://semver.org/lang/zh-CN/)。

## 当前版本

```nix
inputs.cloud.lib.version
# → { major = 0; minor = 3; patch = 0; pre = "dev"; string = "0.3.0-dev"; }
```

`string` 字段适合日志输出，结构字段适合程序判断：

```nix
assert inputs.cloud.lib.version.major == 0;
assert inputs.cloud.lib.version.minor >= 3;
```

## 0.x 阶段承诺

当前处于 `0.x` 阶段，API 仍在演进：

| 类别 | 承诺 |
| ---- | ---- |
| **patch**（0.x.Y） | 仅 bug fix，无破坏性变更 |
| **minor**（0.X.0） | 新增功能；弃用旧 API（trace 警告）；提供迁移说明 |
| **重大变更** | 弃用期不少于 1 个 minor 版本，给出完整迁移路径 |
| **1.0.0** | API 冻结，semver 完整承诺 |

Discovery 约定（目录结构到 output key 的映射）与核心 API（`mkFlake`、`mkSystem`、`mkHome`）在进入 1.0.0 前仍可能调整，但每次变更都会提供迁移说明。

## 弃用流程

1. 新 API 在 minor 版本引入。
2. 旧 API 在同一 minor 版本标记为弃用（`builtins.trace` 警告，但不 `throw`）。
3. 旧 API 在至少 1 个 minor 版本后才会移除。

## 当前弃用项

### mkFlake 扁平参数 → 嵌套命名空间

自 0.3.0 起，`mkFlake` 扁平参数已弃用，使用时会输出 trace 警告：

| 旧（弃用） | 新（推荐） |
| ---------- | ---------- |
| `nixpkgsConfig` | `nixpkgs.config` |
| `extraOverlays` | `nixpkgs.overlays` |
| `extraModules` | 同时加入 `nixos.modules` 与 `home.modules` |
| `extraNixosModules` | `nixos.modules` |
| `extraHomeModules` | `home.modules` |
| `extraSpecialArgs` | `nixos.specialArgs` / `home.specialArgs` |
| `embedHomeManager` | `home.embed` |
| `homeManagerUseGlobalPkgs` | `home.useGlobalPkgs` |
| `extraOutputs` | `outputs.extra` |
| `disabledOutputs` | `outputs.disabled` |
| `expectedOutputs` | `outputs.expected` |

迁移示例：

::: code-group

```nix [旧写法（弃用）]
inputs.cloud.lib.mkFlake {
  inherit inputs;
  nixpkgsConfig = { allowUnfree = true; };
  extraOverlays = [ myOverlay ];
  extraNixosModules = [ myModule ];
  embedHomeManager = true;
  extraOutputs = { hydraJobs = {}; };
  disabledOutputs = [ "checks.broken" ];
}
```

```nix [新写法（推荐）]
inputs.cloud.lib.mkFlake {
  inherit inputs;
  nixpkgs = {
    config = { allowUnfree = true; };
    overlays = [ myOverlay ];
  };
  nixos.modules = [ myModule ];
  home.embed = true;
  outputs = {
    extra = { hydraJobs = {}; };
    disabled = [ "checks.broken" ];
  };
}
```

:::

### meta.nix 旧字段

自 0.3.0 起，hosts `meta.nix` 旧字段已弃用（trace 警告）：

| 旧（弃用） | 新（推荐） |
| ---------- | ---------- |
| `embedHomeManager` | `home.embed` |
| `homeManagerUseGlobalPkgs` | `home.useGlobalPkgs` |
| `homeManager.embed` | `home.embed` |
| `homeManager.useGlobalPkgs` | `home.useGlobalPkgs` |

### cloud.patches.fromPR

已弃用，改用 `cloud.patches.fromCommit`（固定 commit hash，可复现）。

## Feature Detection

在用户仓库模块中可以通过 `version` 做条件处理（例如框架升级过渡期）：

```nix
{ cloud, lib, ... }:
let
  v = cloud.version or { major = 0; minor = 0; patch = 0; };
in
{
  # 0.3+ 才有的特性
  imports = lib.optional (v.minor >= 3) ./new-feature.nix;
}
```

注意：模块参数中的 `cloud` 是精简命名空间，仅包含 `patches`、`sops` 与 `version`，不是完整的 `inputs.cloud.lib`。

## 完整变更记录

见 [CHANGELOG.md](https://github.com/RhenCloud/Cloud-Nix-Framework/blob/main/CHANGELOG.md)。
