# 框架架构

## 整体流程

```
mkFlake 调用
│
├─ [1] 发现阶段（lib/discover.nix）
│       纯文件系统扫描，不求值任何 Nix 配置
│       ├── hosts/       → 列表 + hostsByName
│       ├── homes/       → 列表 + homesByUser + usersByHost
│       ├── modules/     → groupedModules + 模块名索引
│       ├── packages/    → [ { name, path, meta, system? } ]
│       ├── overlays/    → [ { name, path } ]
│       ├── apps/shells/checks/formatter/deploy/lib/
│       └── 禁用过滤（outputs.disabled、meta.enable = false）
│
├─ [2] 构造 overlays / pkgsBySystem
│       每个 system 只实例化并复用一个 package set
│
├─ [3] 构造 nixosConfigurations（惰性）
│       仅 nix build .#nixosConfigurations.foo 时求值
│
├─ [4] 构造 homeConfigurations（惰性）
│
├─ [5] 构造 per-system outputs（惰性）
│       packages / devShells / checks / apps / formatter
│
├─ [6] 构造 images（惰性）
│       按 meta.images.formats 索引构造；访问 images.<host>.<format> 时求值该主机配置
│
├─ [7] 按 outputs.diagnostics 生成诊断 checks
│       discovery JSON / 全局 DOT / per-host DOT
│
└─ [8] lib.recursiveUpdate generated outputs.extra
```

**关键保证**：步骤 [1] 是纯文件系统扫描。步骤 [3]–[7] 均为惰性属性集，`nix flake show` 或查询单个 output 不会触发其他 output 的求值。发现结果按名称建立索引；模块选择、主机 metadata 和依赖解析按主机缓存；同一 `mkFlake` 调用内的 packages、apps、shells、checks、formatter、NixOS 与 Home Manager 复用对应 system 的 `pkgs`。

## 库文件结构

```
lib/
├── default.nix     # mkFlake / mkSystem / mkHome / mkLib 入口
├── discover.nix    # 文件系统发现（hosts/homes/packages/...）
├── host.nix        # meta.nix 解析、角色过滤、HM 策略
├── sops.nix        # sops helper（可选扩展）
├── patches.nix     # patch helper（可选扩展）
└── fs.nix          # 文件系统遍历工具
```

## 模块注入顺序（NixOS 主机）

框架按以下顺序合并模块，后者优先级高于前者：

```
1. optionsCloud（框架 options 声明：cloud.users、cloud.homeManager.*）
2. setCloudModule（写入 config.cloud.users）
3. nixpkgs.pkgs 注入
4. embedModule（home-manager NixOS 模块，仅当启用嵌入且 users != []）
5. 自动发现的 modules/（按角色过滤后进行稳定拓扑排序）
6. moduleRegistries 中的外部模块
7. 主机自身的 default.nix
8. mkFlake 的 nixos.modules / mkSystem 的 extraModules
9. mkSystem 的 extraNixosModules
```

## specialArgs 注入路径

所有 NixOS 模块均收到：`inputs`、`self`、`cloud`（含 `patches`、`sops`）以及 `nixos.specialArgs`。

嵌入式 home-manager 的 specialArgs 写入 `home-manager.extraSpecialArgs`，与独立 HM 行为一致。

## meta.nix 处理

```
meta.nix
    ↓
lib/host.nix: normalizeHostMetadata
    ↓
{ system, roles, home.embed, home.useGlobalPkgs, images.formats }

default.nix
    ↓
NixOS module system（直接 import，不预处理）
```

`meta.nix` 必须是纯属性集（`{ ... }`），在发现阶段求值，与 NixOS 求值阶段完全分离。
