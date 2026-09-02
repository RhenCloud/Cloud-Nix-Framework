# Module Dependency System 设计方案

> 状态：已实现（0.5.0）
> 关联实现：`lib/fs.nix`、`lib/discover.nix`、`lib/internal/depgraph.nix`、`lib/internal/modules.nix`、`lib/default.nix`
> 关联文档：[模块依赖系统](/guide/module-dependencies)、[发现机制](/concepts/discovery)、[Discovery 规范](/reference/discovery)、[细粒度模块控制](/guide/module-overrides)

本文说明模块之间的依赖语义、discovery / composition 两阶段如何建立和解析 module graph，以及实现边界与兼容策略。

## 1. 模块之间的依赖关系

框架区分以下关系：

| 关系 | 声明 | 是否要求目标启用 | 排序效果 |
| ---- | ---- | ---------------- | -------- |
| 硬依赖 | `requires` | 是 | 目标先于当前模块 |
| 后置顺序 | `after` | 否 | 双方启用时目标先于当前模块 |
| 前置顺序 | `before` | 否 | 双方启用时当前模块先于目标 |
| 弱依赖 | `wants` | 否 | 双方启用时目标先于当前模块 |
| 冲突 | `conflicts` | 双方不能同时启用 | 无 |

### 1.1 选项依赖与模块依赖

NixOS / home-manager 模块系统会惰性合并 option 定义，因此读取另一个模块声明的 option 通常不依赖导入列表中的先后位置。但是，消费方和声明方必须同时存在。

跨目录模块存在这种共存要求时，应使用 `requires` 显式声明。这样，当目标被角色过滤或主机覆盖禁用时，框架会在 composition 阶段给出依赖错误，而不是把问题推迟到深层 option 求值。

### 1.2 加载顺序

目录内顺序固定为：

- NixOS：`options.nix` → `default.nix` → `nixos.nix`；
- home-manager：`options.nix` → `default.nix` → `home.nix`。

目录间先按依赖边执行稳定拓扑排序；多个节点同时可选时选择模块名字典序最小的节点。因此，没有依赖元数据时，顺序退化为原有字典序。

### 1.3 两侧独立

NixOS 与 home-manager 使用两张独立的图。所有引用都在当前侧解析，不支持跨侧 `requires`。如果目标只存在于另一侧，当前侧会将其视为未知模块。

## 2. 两阶段图模型

### 2.1 Discovery：建立全局图

`fs.groupModules` 扫描模块 magic 文件并读取同目录的纯数据 `meta.nix`，返回：

```nix
{
  nixos = {
    "desktop.example" = [ /path/options.nix /path/default.nix /path/nixos.nix ];
  };
  home = {
    "desktop.example" = [ /path/options.nix /path/default.nix /path/home.nix ];
  };
  meta = {
    "desktop.example" = {
      path = /path/meta.nix;
      value = { };
    };
  };
}
```

`discover.nix` 为两侧分别调用 `depGraph.buildGraph`，产出：

```nix
moduleGraph = {
  nixos = {
    nodes = { };
    edges = [ ];
    order = [ ];
    side = "nixos";
  };
  home = {
    nodes = { };
    edges = [ ];
    order = [ ];
    side = "home";
  };
};
```

Discovery 阶段负责：

1. 归一化字段和默认值；
2. 应用 `nixos.enable` / `home.enable`；
3. 校验字段类型、未知引用、自引用及 `requires` / `conflicts` 矛盾；
4. 建立排序边并检测全局环；
5. 生成全局稳定拓扑序。

此阶段只导入纯数据 `meta.nix`，不会导入或求值模块实现文件。

### 2.2 Composition：解析每个目标的启用子图

`mkSystem`、独立 `mkHome` 和嵌入式 home-manager 使用相同的本地模块选择流程：

```text
全局图
  → role 过滤
  → 主机 modules 覆盖
  → requires 完整性校验
  → conflicts 校验
  → 启用子图稳定拓扑排序
  → 展开为路径列表
  → 追加 registry / host / home / 显式模块
```

`modules."<name>" = true` 可以显式启用被 role 过滤的本地模块；`false` 禁用整个模块目录；`null` 等价于不覆盖。

`requires` 不会自动启用目标模块。缺失硬依赖会直接失败，避免依赖声明暗中改变主机的功能集合。

## 3. 元数据 Schema

```nix
# modules/desktop/hyprland/meta.nix
{
  requires = [ "desktop.base" ];
  after = [ "desktop.fonts" ];
  before = [ "desktop.portal" ];
  wants = [ "desktop.gaming" ];
  conflicts = [ "desktop.gnome" ];

  nixos.enable = true;
  home.enable = false;
}
```

规则：

- 文件必须直接返回属性集，不能返回函数；
- 五个关系字段必须是字符串列表，默认均为 `[]`；
- `nixos.enable` / `home.enable` 必须是布尔值，默认均为 `true`；
- 引用必须使用由目录推导的完整点分模块名；
- `requires` 蕴含 `after`，无需重复声明；
- `wants` 和 `after` 的排序效果相同，但表达的设计意图不同；
- `conflicts` 按无向关系检测，只需任意一侧声明。

只有包含至少一个 magic 文件的目录才构成模块节点。仅有 `meta.nix` 的目录会被忽略。

## 4. 图表示与算法

### 4.1 边方向

报告中的边使用“当前模块指向它必须排在其后的前驱模块”这一方向：

```json
{ "from": "desktop.hyprland", "to": "desktop.base", "kind": "requires" }
```

含义是 `desktop.base` 先于 `desktop.hyprland`。`after` 和 `wants` 使用相同方向；`before` 会转换为反向排序边。

### 4.2 稳定拓扑排序

算法使用 Kahn 拓扑排序：

1. 在剩余节点中找出所有前驱均已输出的节点；
2. 按模块名字典序排序；
3. 每次取最小节点；
4. 若仍有节点但不存在可选节点，则沿剩余边提取一条环并报错。

该策略保证文件系统读取顺序不影响结果，并保持无依赖仓库的历史顺序。

### 4.3 每目标校验

对目标启用集合 `S`：

1. 对每个 `m ∈ S`，检查 `m.requires` 是否全部属于 `S`；
2. 检查 `S` 中是否存在冲突对；
3. 在 `S` 的诱导子图上重新执行稳定拓扑排序；
4. `after` / `before` / `wants` 指向未启用节点时忽略该顺序边。

缺失依赖错误会附带目标名称、依赖方、缺失模块以及“角色未选中”或“主机显式禁用”等原因。

## 5. 与现有机制的交互

| 机制 | 行为 |
| ---- | ---- |
| `options.nix` / `default.nix` | 仍在两侧注入，并在目录内优先于专属实现 |
| `_common` | 仍绕过 role 过滤，但可被主机覆盖显式禁用 |
| role 过滤 | 先裁剪模块路径，再解析启用子图 |
| 主机 `modules` 覆盖 | `true` 可补回 role 未选中的本地模块，`false` 可触发硬依赖错误 |
| `moduleRegistries` | 当前没有本地模块名，不进图，固定追加在本地模块之后 |
| `hosts/<host>/default.nix` | 作为终端模块追加，不进图 |
| `homes/<user>/*.nix` | 作为终端模块追加，不进图 |
| `nixosModules` / `homeModules` outputs | 仍输出目录组 `{ imports = paths; }`，不会携带图解析器 |

## 6. 可观测性

`checks.<system>.snowveil-discovery` JSON 报告包含全局图与每主机结果：

```json
{
  "moduleGraph": {
    "nixos": {
      "nodes": ["_common.always", "desktop.example"],
      "edges": [
        {
          "from": "desktop.example",
          "to": "_common.always",
          "kind": "requires"
        }
      ],
      "order": ["_common.always", "desktop.example"]
    },
    "home": {
      "nodes": [],
      "edges": [],
      "order": []
    }
  },
  "perHost": {
    "nixos-desktop": {
      "nixos": {
        "enabled": ["_common.always", "desktop.example"],
        "disabled": ["server.demo"],
        "disabledReasons": {
          "server.demo": "未被角色过滤选中"
        }
      },
      "home": {
        "enabled": [],
        "disabled": [],
        "disabledReasons": {}
      }
    }
  }
}
```

## 7. 错误类别

发现阶段错误：

- `meta.nix` 或字段类型错误；
- 当前侧引用未知模块；
- 模块引用自身；
- `requires` 与 `conflicts` 相互矛盾；
- 全局依赖或顺序环。

组合阶段错误：

- 已启用模块缺少硬依赖；
- 同一目标启用了冲突模块；
- 启用子图形成环。

错误示例：

```text
error: 主机 'nixos-desktop' 的模块依赖不完整（nixos 侧）

  - 'desktop.hyprland' 依赖 'desktop.base'，但后者未启用（被主机模块覆盖显式禁用）

提示：启用所需模块，或移除依赖声明
```

## 8. 实现拆分

| 文件 | 职责 |
| ---- | ---- |
| `lib/fs.nix` | 发现模块组、固定目录内顺序、读取模块 `meta.nix` |
| `lib/internal/depgraph.nix` | 图归一化、结构校验、拓扑排序、每目标解析 |
| `lib/discover.nix` | 建立 NixOS / home 两张全局图并按全局顺序扁平化 |
| `lib/internal/modules.nix` | 模块名解析、主机覆盖校验与路径过滤 |
| `lib/default.nix` | role / override 选择、每目标解析、composition 接入与报告生成 |
| `flake.nix` | 正例、顺序断言及环、未知依赖、缺失硬依赖、冲突负例 |
| `examples/basic` | 可运行的依赖元数据示例 |

## 9. 兼容性与后续

- 无 `meta.nix` 的模块没有边，稳定拓扑排序退化为字典序；
- 空 `meta.nix` 等价于 `{}`；
- `groupModules` 保留 `nixos` / `home`，新增 `meta`；`importModules` 输出不变；
- registry 模块保持原有追加位置；
- 版本提升为 `0.5.0-dev`，Discovery Specification 提升为 v1.1。

后续候选：

- 为 `moduleRegistries` 增加命名节点并纳入图；
- 由独立 Snowveil CLI 消费 discovery JSON 和 DOT，提供交互式 `graph` / `why` 命令。
