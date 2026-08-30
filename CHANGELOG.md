# Changelog

所有重要变更记录于此文件。格式参考 [Keep a Changelog](https://keepachangelog.com/zh-CN/1.0.0/)，版本号遵循 [Semantic Versioning](https://semver.org/lang/zh-CN/)。

---

## [Unreleased] — 0.3.0-dev

### 新增

- `cloud.lib.version`：框架版本号，包含 `major`、`minor`、`patch`、`pre`、`string` 字段，支持 feature detection。
- `mkFlake` 嵌套命名空间参数（推荐）：
  - `nixpkgs.config` → 替代 `nixpkgsConfig`
  - `nixpkgs.overlays` → 替代 `extraOverlays`
  - `nixos.modules` / `home.modules` → 替代跨两侧注入的 `extraModules`
  - `nixos.modules` → 替代 `extraNixosModules`（专属 NixOS 侧）
  - `nixos.specialArgs` → 替代 `extraSpecialArgs`（NixOS 侧）
  - `home.modules` → 替代 `extraHomeModules`
  - `home.embed` → 替代全局 `embedHomeManager`
  - `home.useGlobalPkgs` → 替代全局 `homeManagerUseGlobalPkgs`
  - `outputs.extra` → 替代 `extraOutputs`
  - `outputs.disabled` → 替代 `disabledOutputs`
  - `outputs.expected` → 替代 `expectedOutputs`
- `meta.nix` 规范字段 `home.embed` / `home.useGlobalPkgs`，替代旧字段（旧字段仍兼容）。
- `cloud.sops.secret { source = "host"; }` 省略 `host` 时自动从 `config.networking.hostName` 推导。
- `cloud.homeManager.backupFileExtension` NixOS option，可在公共模块中安全使用（无需判断 HM 嵌入状态）。
- `expectedOutputs` 校验：`mkFlake` 支持声明期望的 hosts/homes/packages/apps，`cloud-discovery` check 会验证。
- 文档重构：guide / concepts / reference / migration / advanced 五区分层。
- Discovery 规范文档（`docs/reference/discovery.md`）。

### 变更

- `meta.nix` 与 `default.nix` 职责严格分离：`default.nix` 不再被 CNF 解析元数据，只交给 NixOS module system。
- `lib/default.nix` 拆分为 `discover.nix`、`host.nix`、`sops.nix` 等独立文件，发现逻辑与系统构造逻辑分离。
- overlay 签名检测升级：通过 `functionArgs` 自动识别解构签名（`{ inputs, self, cloud }: final: prev: ...`）与位置参数签名（`extras: final: prev: ...`）。
- `cloud.patches.fromPR` 标记为已弃用，推荐使用 `cloud.patches.fromCommit`（固定 commit hash，可复现）。

### 弃用（仍兼容，至少保留一个 minor 版本）

`mkFlake` 扁平参数（使用时会输出 `builtins.trace` 警告）：

| 旧参数 | 新参数 |
| ------ | ------ |
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

`meta.nix` 旧字段（使用时会输出 `builtins.trace` 警告）：

| 旧字段 | 新字段 |
| ------ | ------ |
| `embedHomeManager` | `home.embed` |
| `homeManagerUseGlobalPkgs` | `home.useGlobalPkgs` |
| `homeManager.embed` | `home.embed` |
| `homeManager.useGlobalPkgs` | `home.useGlobalPkgs` |
| `role`（单值） | `roles`（列表，仍兼容） |

---

## [0.2.0] — 2026-07

### 新增

- `disabledOutputs`：支持字符串列表和 output 名到名称列表的属性集两种形式。
- Per-host Home Manager 策略：`embedHomeManager` / `homeManagerUseGlobalPkgs` 支持全局值、函数和 per-host 属性集。
- `meta.nix` 主机元数据：`roles`、`embedHomeManager`、`homeManagerUseGlobalPkgs`、`images.formats`。
- system-first package 布局：`packages/<system>/<name>/default.nix`（推荐，无歧义）。
- `cloud.sops` helper：`commonFile`、`hostFile`、`defaultFile`、`secret`、`mkModule`。
- `cloud-discovery` check：框架保留 check，输出 JSON 发现报告。
- `images`：通过 `meta.nix.images.formats` 或模块 `config.cloud.images.formats` 声明镜像格式。
- overlay 自动应用到所有 pkgs 实例（NixOS、HM 独立/嵌入、packages、checks 等）。
- Overlay 扩展签名检测（`functionArgs` + 调用探测）。

### 变更

- `packages/<name>` 使用与 NixOS 相同的统一 pkgs（含 `nixpkgsConfig` 与 overlays），不再使用 `legacyPackages`。
- 模块注入顺序文档化并稳定（字典序排序，可复现）。
- HM `extraSpecialArgs` 正确写入 `home-manager.extraSpecialArgs`，与独立 HM 行为一致。

---

## [0.1.0] — 2026-05

### 初始版本

- `mkFlake`、`mkSystem`、`mkHome`、`mkLib` 核心 API。
- 目录自动发现：`hosts/`、`homes/`、`modules/`、`packages/`、`overlays/`、`apps/`、`shells/`、`checks/`、`formatter/`、`deploy/`、`lib/`。
- 单树模块 + 文件名分拣（`default.nix`、`nixos.nix`、`home.nix`）。
- 角色系统（`roles`）+ `_common` 前缀特殊目录。
- `moduleRegistries`：外部模块按角色注入。
- `cloud.patches.local` / `cloud.patches.fromPR`。
- NixOS + home-manager 双轨，嵌入式 HM 自动注入。
- 模板：`nix flake init --template github:RhenCloud/Cloud-Nix-Framework`。
