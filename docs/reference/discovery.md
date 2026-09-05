# Discovery 规范

本文档定义 **Snowveil Discovery Specification v1.3** —— 框架如何将目录树转译为 flake outputs 的完整规则集。规范以实现为准：`lib/discover.nix` 与 `lib/fs.nix` 是本规范的参考实现。

## 术语

| 术语 | 含义 |
| ---- | ---- |
| **发现**（discovery） | 框架扫描项目目录、识别符合约定的文件并提取元数据的过程 |
| **项目根**（root） | `mkFlake` 调用时的配置仓库根目录，默认为 `self.outPath` |
| **magic 文件** | 具有固定语义的文件名：`default.nix`、`options.nix`、`nixos.nix`、`home.nix`、`meta.nix`，以及主机目录专属的 `hardware.nix`、`disk.nix`、`network.nix` |
| **meta.nix** | 与某目录并列的元数据文件，直接返回属性集，不接收模块参数 |
| **output key** | 最终出现在 flake outputs 属性集中的名称 |

---

## 通用规则

### 遍历顺序

所有目录遍历结果均按**完整相对路径字典序**升序排序，在发现阶段完成。排序保证模块合并顺序稳定、可复现，不依赖 `builtins.readDir` 的返回次序（未定义）。

### meta.nix 约定

- `meta.nix` 必须直接返回属性集（`{ ... }`），不能是函数、模块或其他类型。
- 违反此约定将在发现阶段 `throw` 报错，不会静默忽略。
- 所有目录类型均支持 `meta.nix`，但各目录可用字段不同（见各节）。
- `meta.nix` 不存在时等价于 `{}`，所有字段取各自的规范默认值。

### 禁用优先级

两种禁用机制独立生效，任一满足即禁用：

1. **`meta.nix { enable = false; }`**：在发现阶段之后、output 构造之前过滤。
2. **`mkFlake` 的 `outputs.disabled`**：在 output 构造阶段按名称过滤。

命名冲突（同一 output key 由多条规则产生）：发现阶段提前 `throw`，不进入 output 构造。

---
## hosts/ — NixOS 主机

### 发现规则

扫描范围：`hosts/` 下的**直接子目录**（不递归）。

对每个子目录 `hosts/&lt;dir&gt;/`，按以下优先级推断 output key 与 system：

| 优先级 | 条件 | 结果 |
| :----: | ---- | ---- |
| 1 | `meta.nix` 存在且含 `system = "&lt;system&gt;"` | `name = &lt;dir&gt;`（完整目录名），`system = meta.nix.system` |
| — | 无 `meta.nix` 或缺 `system` 字段 | `throw` 错误（强制要求） |

**必要条件**：`hosts/&lt;dir&gt;/default.nix` 必须存在，否则无论何种形式均静默跳过。

**system 声明**：

- `system` 字段是强制要求，不再支持从目录名后缀推导。
- 各个 `hosts/&lt;name&gt;/` 必须有 `meta.nix`，其中包含 `system` 字段。
- 推荐理由：避免目录名中的点号歧义（FQDN 型主机名无需特殊处理），并显式表达架构声明。

### 主机目录 magic 文件分拣（v1.2）

主机目录除 `default.nix`（必需）与 `meta.nix`（仅元数据）外，框架按固定顺序识别以下可选 magic 文件：**存在则 import，缺失即跳过**。

| 加载顺序 | 文件 | 用途（约定，非强制） |
| :--: | ---- | -------------------- |
| 1 | `default.nix` | 主机意图：主机名、时区、想启用的服务 |
| 2 | `hardware.nix` | 硬件相关配置（可在此 import nixos-hardware 等） |
| 3 | `disk.nix` | 磁盘布局：disko 或原生 `fileSystems` |
| 4 | `network.nix` | 网络配置 |

- 加载顺序固定，与文件系统读取次序无关；主机 magic 文件紧跟在自动发现的 `modules/` 与注册表模块之后注入（`mkSystem`），仅影响 NixOS 侧，不涉及 home-manager 侧。
- 框架只负责分拣与 import，**不内置、不依赖** disko / nixos-hardware；需要时在用户 `flake.nix` 中添加相应 input 并在 `disk.nix` / `hardware.nix` 中使用。
- 主机目录内的其他 `.nix` 文件**不会**被自动导入，发现阶段输出 trace 警告；如需使用请在主机模块中自行 `import`。
- `snowveil-discovery` 报告的 `hostFiles` 字段按主机名列出实际加载的 magic 文件名（按加载顺序）。

### Output 映射

```
hosts/<name>/default.nix            →  nixosConfigurations.<name>
hosts/<name>/hardware.nix           →  可选，存在则随主机自动 import（加载顺序 2）
hosts/<name>/disk.nix               →  可选，存在则随主机自动 import（加载顺序 3）
hosts/<name>/network.nix            →  可选，存在则随主机自动 import（加载顺序 4）
hosts/<name>/meta.nix               →  （仅元数据，必须含 system，不生成 output）
```

### meta.nix 字段（hosts）

| 字段 | 类型 | 默认值 | 说明 |
| ---- | ---- | ------ | ---- |
| `system` | `string` | — | **必需**，架构标识符（无默认值，省略将 throw） |
| `role` | `string` | `null` | 角色过滤标签（单值），与 `roles` 互为别名 |
| `roles` | `[string]` | `null` | 角色过滤标签（多值），`null` 表示不过滤 |
| `home.embed` | `bool` | `null` | 是否将关联 home 嵌入此主机（`null` 表示继承全局策略） |
| `home.useGlobalPkgs` | `bool` | `null` | 嵌入式 HM 是否复用 NixOS pkgs（`null` 表示继承全局策略） |
| `embedHomeManager` | `bool` | `null` | **已弃用**，请使用 `home.embed` |
| `homeManagerUseGlobalPkgs` | `bool` | `null` | **已弃用**，请使用 `home.useGlobalPkgs` |
| `homeManager.embed` | `bool` | `null` | **已弃用**，请使用 `home.embed` |
| `homeManager.useGlobalPkgs` | `bool` | `null` | **已弃用**，请使用 `home.useGlobalPkgs` |
| `images.formats` | `[string]` | `[]` | 需要生成的镜像变体（如 `["iso"]`），在发现阶段读取；实际镜像构建需访问对应主机的 config |

**优先级（高 → 低）**：`meta.nix` 字段 > `mkFlake` 全局参数 > 框架硬编码默认值。

### 注入到 nixosConfigurations

框架按以下顺序合并模块，后者优先级高于前者（NixOS module system 的 `mkDefault`/`mkForce` 仍适用）：

```
1. optionsSnowveil（框架 options 声明）
2. setSnowveilModule（写入 config.snowveil.users）
3. nixpkgs.pkgs 注入
4. userDefaultsModule（users/<name>/meta.nix 生成的 users.users/groups，仅当 users != []）
5. users/<name>/default.nix（用户补充模块，若存在）
6. embedModule（home-manager NixOS 模块，仅当 embedForHost && 关联 home 的 users != []）
7. 自动发现的 modules/（按角色过滤后进行稳定拓扑排序）
8. moduleRegistries 中的外部模块
9. 主机自身的 default.nix（去除框架元数据字段）
10. mkFlake 的 nixos.modules / mkSystem 的 extraModules
11. mkSystem 的 extraNixosModules
```
---

## profiles/ — Profile 定义

### 发现规则

扫描范围：`profiles/` 下的所有 `.nix` 文件（不递归），以及 `mkFlake { profiles = { ... }; }` 参数。

每个 profile 的定义形式：

```nix
# profiles/workstation.nix — 纯列表形式（两侧同时应用）
[ "a.b" "x.y" ]

# profiles/personal.nix — 分侧形式（可选）
{
  common = [ "base" ];           # 两侧都应用
  nixos = [ "nixos-only" ];      # 仅 NixOS 侧
  home = [ "hm-only" ];          # 仅 home-manager 侧
}
```

- 纯列表自动扩展为 `{ common = list; }` 形式。
- 空列表或空属性集视为错误（profile 必须声明至少一个成员）。
- 成员名称必须存在于相应侧的模块图中；未知成员报错。
- 文件 vs 参数冲突（同名 profile）：报错。

### Profile 语义

**Host metadata 中的 profiles 声明**：

```nix
# hosts/mybox/meta.nix
{
  system = "x86_64-linux";
  profiles = [ "workstation" "personal" ];
}
```

- 每个声明的 profile 必须存在；未知 profile 报错。
- 同一主机的多个 profile 成员按顺序合并。
- Profile 成员自动启用，等价于主机级 `modules.<name> = true`。
- 主机级 `modules.<name> = false` 仍可显式禁用 profile 成员（override 优先）。
- Profile 成员仍经过依赖校验、冲突校验、拓扑排序等标准流程。

**与 moduleGroups 的语义差异**：

- `moduleGroups`：模块侧声明的 all-of 硬依赖，不自动启用成员（成员仍需被角色过滤或主机显式启用）。
- `profiles`：主机侧声明的启用包，自动启用成员（除非被 `modules.<name> = false` 覆盖）。

---

## users/ — 系统用户（一等实体）

### 发现规则

扫描范围：`users/` 下的**直接子目录**（每个子目录对应一个用户）。

```
users/<name>/
├── meta.nix        →  用户元数据（必需，声明 hosts 等）
└── default.nix     →  （可选）users.users.<name> 补充模块
```

- `meta.nix` 必须存在，否则该目录被忽略（不报错）。
- `meta.nix` 必须声明 `hosts = [ ... ]`（字符串列表），否则在发现阶段 `throw` 报错。
- `default.nix` 是纯 NixOS 模块，会被注入到该用户所属的每台主机。

### meta.nix 字段（users）

| 字段 | 类型 | 默认值 | 说明 |
| ---- | ---- | ------ | ---- |
| `hosts` | `[string]` | — | **必需**，此用户关联的主机名列表（主机必须已发现） |
| `uid` | `int` | `null` | 系统 UID（`null` 表示由 NixOS 自动分配） |
| `gid` | `int` | `uid` | 主组 GID（缺省取 `uid`） |
| `group` | `string` | `name` | 主组名（缺省与用户名一致） |
| `extraGroups` | `[string]` | `[]` | 附加组 |
| `description` | `string` | `null` | 用户描述 |
| `home` | `string` | `null` | 主目录（`null` 表示 `/home/<name>`） |
| `createHome` | `bool` | `true` | 是否创建主目录 |
| `isNormalUser` | `bool` | `true` | 是否普通用户 |
| `hashedPasswordSecret` | `string` | `null` | 见下方约定 |

### 生成规则

框架在用户关联的每台主机上自动生成 `users.users.<name>` 与 `users.groups.<name>`：

- 核心字段（`isNormalUser`、`home`、`createHome`、`uid`、`extraGroups`、`description`、`hashedPasswordFile`）均用 `mkDefault` 包裹，可被 `users/<name>/default.nix` 或主机模块覆盖。
- `group` 使用普通值（非 `mkDefault`），因为 nixpkgs 在 `isNormalUser = true` 时会对 `group` 施加 `mkDefault "users"`；框架同时生成 `users.groups.<name> = {}`（可选 `gid`）以避免「primary group undefined」断言。
- `uid` 缺省时 NixOS 自动分配；显式 `uid` 且 `isNormalUser = true` 时须 `>= 1000`。

### hashedPasswordSecret 约定

- 值以 `/` 开头 → 视为字面文件路径，直接作为 `hashedPasswordFile`。
- 否则 → sops 密钥名，`hashedPasswordFile` 指向 `config.sops.secrets.<name>.path`，并自动声明 `sops.secrets.<name>`（来源为主机 sops 文件）。

---

## homes/ — Home Manager 配置

### 发现规则

扫描范围：`homes/` 下的**直接子目录**（每个子目录对应一个用户）。

```
homes/<user>/
├── default.nix      →  homeConfigurations.<user>            （全局/共享 home）
├── <host>.nix       →  homeConfigurations."<user>@<host>"   （主机关联 home）
└── <host2>.nix      →  homeConfigurations."<user>@<host2>"  （主机关联 home）
```

- `&lt;host&gt;` 必须与 `hosts/` 中已发现的某主机 name 完全一致，否则该文件被忽略（不报错）。
- `default.nix` 专用于全局 home，不会生成 `&lt;user&gt;@default` output。
- 同一用户目录下可同时存在 `default.nix` 与若干 `&lt;host&gt;.nix`，互不冲突。
- 子目录遍历**不递归**；`homes/&lt;user&gt;/sub/foo.nix` 会被忽略。

### Output 映射

| 文件 | output key | system 来源 |
| ---- | ---------- | ----------- |
| `homes/&lt;user&gt;/default.nix` | `homeConfigurations.&lt;user&gt;` | `mkFlake` 的 `systems` 首项 |
| `homes/&lt;user&gt;/&lt;host&gt;.nix` | `homeConfigurations."&lt;user&gt;@&lt;host&gt;"` | 对应主机目录的 system |

::: warning 全局 home 的 system

`homeConfigurations.&lt;user&gt;` 使用 `systems` 的第一个元素作为 system。若 `systems` 含多个架构，全局 home 将只对第一个架构有效。需要多架构全局 home 时，建议将用户明确关联到各架构的主机（通过 `&lt;host&gt;.nix`），或在 `homes/&lt;user&gt;/meta.nix` 中声明 `system`（待实现）。

:::
    
    ### 自动嵌入 NixOS
        
    当 `users/&lt;name&gt;/meta.nix` 的 `hosts` 包含该主机，且 `homes/&lt;name&gt;/&lt;host&gt;.nix` 存在时：
    
1. 框架将 `&lt;name&gt;` 写入 `nixosConfigurations.&lt;host&gt;` 的 `config.snowveil.users`。
2. 若该主机的 `home.embed` 为 `true`，框架自动注入 `home-manager.users.&lt;name&gt;` 模块（无需在主机模块中手写 `home-manager.users`）。
3. 若 `home.embed` 为 `false`，仅生成独立的 `homeConfigurations."&lt;name&gt;@&lt;host&gt;"`，不嵌入 NixOS。

### 模块注入顺序（独立 home）

```
1. optionsSnowveilHome（框架 options 声明）
2. 自动发现的 modules/（home 侧，按角色过滤后进行稳定拓扑排序）
3. homes/<user>/default.nix（若存在）
4. homes/<user>/<host>.nix（若存在且当前构造的是 per-host home）
5. mkFlake 的 home.modules / mkHome 的 extraModules
6. mkHome 的 extraHomeModules
```

### meta.nix 字段（homes）

homes 目录当前不读取 `meta.nix`；保留位置供未来使用（如声明全局 home 的 system）。

---

## modules/ — 自动发现模块

### 发现规则

扫描范围：`modules/` 下的**全部层级**（递归遍历）。

识别以下 magic 文件名：

| 文件名 | 注入到 | 含义 |
| ------ | ------ | ---- |
| `options.nix` | NixOS 侧 + HM 侧 | 共享 option 接口声明 |
| `default.nix` | NixOS 侧 + HM 侧 | 平台中性共享实现 |
| `nixos.nix` | NixOS 侧 | NixOS 专属实现 |
| `home.nix` | HM 侧 | Home Manager 专属实现 |

同一目录可同时存在多个 magic 文件；无 magic 文件的目录被忽略。

### 模块名推导

```
modules/<path>/options.nix  →  模块名 = path（以 "/" 替换为 "."）
modules/<path>/default.nix  →  同上
modules/<path>/nixos.nix    →  同上
modules/<path>/home.nix     →  同上
```

示例：`modules/desktop/hyprland/nixos.nix` → 模块名 `desktop.hyprland`

模块名重复（不同路径映射到同一名称）时，发现阶段 `throw` 报错。

### 角色过滤

当主机 `meta.nix` 声明了 `roles`，框架只注入满足以下任一条件的模块路径：

1. 文件名是 `options.nix` 或 `default.nix`（共享接口与平台中性实现始终注入）。
2. 第一级目录名以 `_` 开头（common 约定，始终注入，如 `modules/_common/`）。
3. 第一级目录名与某个角色名完全一致。

**`roles = null`（未声明）时不过滤**，所有发现的模块均注入。

### Output 映射（模块注册表）

自动发现的模块还生成以下 flake outputs，供外部 flake 引用：

```
nixosModules.<name>   →  { imports = [ <所有属于该目录组的 NixOS 侧路径> ]; }
homeModules.<name>    →  { imports = [ <所有属于该目录组的 HM 侧路径> ]; }
```

`&lt;name&gt;` 即上述模块名（点分路径）。

### meta.nix 字段（modules）

每个模块目录可用 `meta.nix` 声明依赖关系。文件必须直接返回属性集：

```nix
{
  requires = [ "desktop.base" ];
  after = [ "desktop.fonts" ];
  before = [ "desktop.portal" ];
  wants = [ "desktop.gaming" ];
  conflicts = [ "desktop.gnome" ];

  nixos = {
    enable = true;
    requires = [ "nixos.base" ];
  };
  home = {
    enable = false;
    requires = [ "home.base" ];
  };

  requiresGroups = [ "desktop-stack" ];
  provides = [ "desktop-session" ];
  requiresCapabilities = [ "display-server" ];
}
```

| 字段 | 类型 | 默认值 | 语义 |
| ---- | ---- | ------ | ---- |
| `requires` | `[string]` | `[]` | 同侧硬依赖；依赖项未启用时组合失败，同时蕴含 `after` |
| `after` | `[string]` | `[]` | 软顺序约束；双方启用时当前模块排在目标之后 |
| `before` | `[string]` | `[]` | 软顺序约束；双方启用时当前模块排在目标之前 |
| `wants` | `[string]` | `[]` | 弱依赖；目标存在且启用时排在目标之后，未启用不报错 |
| `conflicts` | `[string]` | `[]` | 互斥模块；双方同时启用时组合失败 |
| `nixos.enable` | `bool` | `true` | 是否在 NixOS 侧参与自动注入与依赖图 |
| `home.enable` | `bool` | `true` | 是否在 home-manager 侧参与自动注入与依赖图 |
| `nixos/home.<关系字段>` | `[string]` | `[]` | 追加到当前侧的共享关系字段 |
| `requiresGroups` | `[string]` | `[]` | 引用 `mkFlake.moduleGroups`，展开为 all-of 硬依赖 |
| `provides` | `[string]` | `[]` | 当前模块提供的虚拟能力 |
| `requiresCapabilities` | `[string]` | `[]` | 要求已启用集合至少包含一个 provider |

所有关系字段采用“顶层共享 + 当前侧追加”语义。模块组在 `mkFlake.moduleGroups` 全局注册，列表形式两侧共享，属性集形式由 `common + 当前侧` 组成。组和能力均不自动启用模块。

所有引用使用点分模块名，不支持路径或通配符。引用未知模块或组、自依赖、硬依赖与冲突矛盾、缺失能力和依赖环均会报错。

组合时先执行角色过滤与主机 `modules` 覆盖，再校验 `requires` 闭包和 `conflicts`，最后进行稳定拓扑排序。多个节点同时可选时按模块名字典序排列，因此没有依赖元数据的仓库保持原有顺序。

---
## packages/ — 包

### 发现规则（三种布局，按优先级）

框架支持三种 package 布局，解析时按以下顺序检查，三者可共存：

| 布局 | 目录约定 | system 来源 | 推荐程度 |
| ---- | -------- | ----------- | -------- |
| **system-first**（推荐） | `packages/&lt;system&gt;/&lt;name&gt;/default.nix` | 目录名即 system | ★★★ |
| **无后缀**（跨平台） | `packages/&lt;name&gt;/default.nix` | 所有 `systems` | ★★★ |
| **后缀兼容**（旧式） | `packages/&lt;name&gt;.&lt;system&gt;/default.nix` | 目录后缀解析 | ★（已不推荐） |

**解析优先级（system-first 优先）**：

对 `packages/` 下的一级目录 `&lt;dir&gt;`：

1. 若 `&lt;dir&gt;` 本身有 `default.nix`，归为"无后缀"或"后缀兼容"布局。
2. 若 `&lt;dir&gt;` 没有 `default.nix`，将 `&lt;dir&gt;` 视为 system 名，递归发现其子目录作为 system-first 包。

这意味着 system-first 与无后缀布局**不能共用同一个一级目录名**：若 `packages/x86_64-linux/` 下存在 `default.nix`，该目录被视为包而不是 system 前缀。

**后缀兼容解析细节**（仅当 `meta.nix` 未声明 `systems` 时触发）：

```
packages/<name>.<system>/default.nix
  packages/<name> = lib.splitString "." <dir>  →  init 部分
  <system> = last 部分
  有效要求：最后一段在 knownSystems 中
            （knownSystems = systems ++ lib.systems.flakeExposed）
```

若 `meta.nix` 显式声明了 `systems`，完整目录名作为包名，不拆分后缀。

### Output 映射

```
packages/<name>/default.nix            →  packages.<system>.<name>   （对所有 systems）
packages/<system>/<name>/default.nix   →  packages.<system>.<name>   （仅对应 system）
packages/<name>.<system>/default.nix   →  packages.<system>.<name>   （旧式，不推荐）
```

### meta.nix 字段（packages）

| 字段 | 类型 | 默认值 | 说明 |
| ---- | ---- | ------ | ---- |
| `enable` | `bool` | `true` | 是否生成此 output |
| `systems` | `[string]` | `null` | 显式指定支持的架构列表；声明后禁用后缀兼容解析 |

### callPackage 调用约定

框架用 `pkgs.callPackage` 调用包文件，额外注入 `{ inputs, self, snowveil }`（若包函数声明了这些参数）。

---

## overlays/ — Nixpkgs Overlays

### 发现规则

扫描范围：`overlays/` 下的**直接子目录**。

必要条件：`overlays/&lt;name&gt;/default.nix` 存在。

### Output 映射

```
overlays/<name>/default.nix  →  overlays.<name>
```

所有自动发现的 overlays 自动应用到：NixOS pkgs、独立 HM pkgs、嵌入式 HM pkgs（当 `useGlobalPkgs = false` 时）、packages / devShells / checks / apps / formatter 的 pkgs。

### Overlay 文件签名

框架按以下规则检测签名：

1. `functionArgs` 含 `inputs`、`self` 或 `snowveil` → 解构框架参数签名，调用 `imported { inherit inputs self snowveil; }`。
2. 其余 → 标准 nixpkgs overlay（`final: prev: ...` 或直接返回属性集，但后者会在 nixpkgs 应用时报错）。

### meta.nix 字段（overlays）

overlays 目录当前不读取 `meta.nix`。

---

## apps/ / shells/ / checks/ — 命名 per-system outputs

### 发现规则

三个目录采用相同规则，扫描范围均为**直接子目录**：

```
apps/<name>/default.nix    →  apps.<system>.<name>
shells/<name>/default.nix  →  devShells.<system>.<name>
checks/<name>/default.nix  →  checks.<system>.<name>
```

### meta.nix 字段

| 字段 | 类型 | 默认值 | 说明 |
| ---- | ---- | ------ | ---- |
| `enable` | `bool` | `true` | 是否生成此 output |
| `systems` | `[string]` | `null` | 限定支持的架构 |

### 保留名称

`checks/` 下以 `snowveil-` 开头的名称是框架保留命名空间，用于 discovery、expected、eval 和 DOT 检查；发现阶段遇到冲突会直接报错。

---

## formatter/ / deploy/ — 单例 outputs

```
formatter/default.nix  →  formatter.<system>   （per-system）
deploy/default.nix     →  deploy               （全局单例）
```

- 两者均只扫描固定路径，不递归。
- `formatter` 是 per-system output，`deploy` 是全局单例。
- `meta.nix` 支持 `enable`（`bool`）；`formatter` 额外支持 `systems`。

---

## lib/ — 用户库函数

```
lib/<name>.nix  →  lib.<name>
```

- 扫描范围：`lib/` 下的**直接 .nix 文件**（不递归，不含子目录）。
- output key 为去掉 `.nix` 后缀的文件名。
- 框架用 `importFile` 调用，注入 `{ lib, inputs, self, snowveil }`（按函数声明按需传入）。
- 框架自身的 `lib/` 文件（`discover.nix`、`host.nix` 等）不在扫描范围内。

---

## 发现流程全图

```
mkFlake 调用
│
├─ [1] 读取 lib/discover.nix（发现阶段，纯属性集，不求值 config）
│       ├── hosts/       → discovered.hosts      [ { name, system, path, modulePaths, meta } ]
│       ├── users/       → discovered.users      [ { name, metaPath, defaultPath, hosts } ]
│       ├── homes/       → discovered.homes      [ { user, hosts } ]
│       ├── modules/     → discovered.localGroupedModules / localAutoModules
│       ├── packages/    → discovered.packages   [ { name, path, meta, explicitSystem } ]
│       ├── overlays/    → discovered.overlays   [ { name, path } ]
│       ├── apps/        → discovered.apps
│       ├── shells/      → discovered.shells
│       ├── checks/      → discovered.checks
│       ├── formatter/   → discovered.formatter  ( { path, meta } | null )
│       ├── deploy/      → discovered.deploy     ( { path, meta } | null )
│       └── lib/         → discovered.libFiles   [ { name } ]
│
├─ [2] 构造 overlays / pkgsBySystem（每个 system 复用一个 package set）
│
├─ [3] 构造 nixosConfigurations（惰性；仅 nix build .#nixosConfigurations.foo 时求值）
│
├─ [4] 构造 homeConfigurations（惰性）
│
├─ [5] 构造 packages / devShells / checks / apps / formatter（惰性，per-system）
│
├─ [6] 构造 images（按 meta.images.formats 索引；访问具体值时求值对应主机）
│
├─ [7] 按 outputs.diagnostics 生成框架保留的 discovery / 模块图 checks
│
└─ [8] lib.recursiveUpdate generated outputs.extra
```

**关键保证**：步骤 [1] 是纯文件系统扫描，不求值任何 Nix 配置。步骤 [3]–[7] 均为惰性属性集，`nix flake show` 或查询单个 output 不会触发其他 output 的求值。

---

## 约定变更与兼容性

| 版本 | 变更 |
| ---- | ---- |
| v1（当前） | 三种 package 布局并存；host dir 后缀解析 |
| 建议 v2 | 弃用 `packages/&lt;name&gt;.&lt;system&gt;/` 旧式后缀布局；仅保留 system-first 与无后缀两种 |

旧式后缀布局在 `meta.nix` 未声明 `systems` 时继续兼容，但不推荐用于新配置。

---

*本规范版本：v1.2。实现位置：`lib/discover.nix`、`lib/fs.nix`、`lib/host.nix`、`lib/default.nix`。*

## Discovery 报告契约

`checks.<system>.snowveil-discovery` 顶层包含 `schemaVersion = 1`、`discoverySpecVersion = "1.3"`、`frameworkVersion` 与 `system`。JSON schema major 只在破坏性结构变化时递增；规范版本独立演进。`hostFiles` 为主机名到实际加载的主机目录 magic 文件列表（按加载顺序）的映射。`profiles` 为 profile 定义映射，`hostProfiles` 为主机声明的 profile 名稱映射。用户 `checks/` 名称不得使用框架保留的 `snowveil-` 前缀。

发现阶段同时维护 `hostsByName`、`usersByName`、`homesByUser`、`usersByHost` 与模块名索引，后续组合阶段不再重复扫描 users/homes 路径或按列表线性查找主机。`outputs.diagnostics.perHostModuleGraph = false` 时，报告中的 `perHost` 为 `{}`，DOT 输出也省略 `hosts/` 子目录。
