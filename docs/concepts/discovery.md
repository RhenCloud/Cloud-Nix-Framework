# 发现机制

发现（Discovery）是框架将目录树转译为 flake outputs 的核心机制。本页解释发现的原理；完整字段规范见[《Discovery 规范》](/reference/discovery)。

## 什么是发现

发现阶段是**纯文件系统扫描**：

- 读取目录结构和 `meta.nix` 文件
- 不求值任何 NixOS 或 home-manager 配置
- 产出一个属性集（发现清单），传给后续构造阶段

这意味着 `nix flake show` 不会触发所有主机的 config 求值。

## 发现对象

| 目录 | 发现什么 | 映射到 |
| ---- | -------- | ------ |
| `hosts/` | NixOS 主机 | `nixosConfigurations` |
| `homes/` | HM 配置 | `homeConfigurations` |
| `modules/` | 模块组 | `nixosModules`、`homeModules` |
| `packages/` | 包 | `packages` |
| `overlays/` | Overlay | `overlays` |
| `apps/` | App | `apps` |
| `shells/` | Dev shell | `devShells` |
| `checks/` | 检查 | `checks` |
| `formatter/` | 格式化器 | `formatter` |
| `deploy/` | 部署配置 | `deploy` |
| `lib/` | 用户库函数 | `lib` |

## 角色过滤

发现清单构建后，框架根据每台主机的 `roles` 过滤要注入的模块：

```
modules/_common/**   → 始终注入
modules/<role>/**    → 仅注入声明了该 role 的主机
default.nix          → 始终注入（共享 option）
```

未声明 `roles` 的主机全量注入（向后兼容）。

## 发现调试

`checks.<system>.cloud-discovery` 是带版本元数据的稳定 JSON 报告：

```bash
nix build .#checks.x86_64-linux.cloud-discovery
cat result
```

```json
{
  "schemaVersion": 1,
  "discoverySpecVersion": "1.1",
  "frameworkVersion": "0.5.0-dev",
  "system": "x86_64-linux",
  "hosts": ["nixos-desktop"],
  "packages": ["hello"],
  "moduleGraph": {
    "nixos": {
      "nodes": ["desktop.example"],
      "edges": [],
      "order": ["desktop.example"],
      "groups": {},
      "capabilities": {},
      "details": {}
    }
  },
  "perHost": {}
}
```

`schemaVersion` 只在 JSON 结构发生破坏性变化时递增；`discoverySpecVersion` 独立表示目录发现规范。所有集合和图数据以稳定、可复现的顺序输出。

DOT 图由 `checks.<system>.cloud-module-graph-dot` 输出，包含全局图和 `hosts/<host>/<side>.dot`。

## 命名冲突

同一 output key 由多条规则产生时，发现阶段提前 `throw`，不进入构造阶段。

## 保留名称

`checks/` 下所有以 `cloud-` 开头的名称均由框架保留，包括 discovery、expected、eval 和 DOT 检查。
