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

`checks.<system>.cloud-discovery` 是框架自动生成的 JSON 报告，列出所有发现结果：

```bash
nix build .#checks.x86_64-linux.cloud-discovery
cat result
```

输出示例：

```json
{
  "hosts": ["nixos-desktop", "nixos-server"],
  "homes": ["rhencloud@nixos-desktop"],
  "packages": { "x86_64-linux": ["hello"] },
  "modules": { "nixosModules": [...], "homeModules": [...] }
}
```

## 命名冲突

同一 output key 由多条规则产生时，发现阶段提前 `throw`，不进入构造阶段。

## 保留名称

`checks.<system>.cloud-discovery` 是框架保留名称。用户 `checks/` 目录下不能有 `cloud-discovery/` 子目录，否则发现阶段报错。
