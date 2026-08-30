# 角色系统

角色（role）是框架的**模块过滤机制**：通过在主机元数据中声明角色，自动决定哪些目录下的模块会被注入该主机。

## 声明角色

在 `meta.nix` 中声明（推荐）：

```nix
# hosts/nixos-desktop.x86_64-linux/meta.nix
{
  roles = [
    "desktop"
    "development"
  ];
}
```

`role`（单值）是 `roles`（列表）的别名，两者等价。

## 模块目录结构

```
modules/
├── _common/          # 始终注入（特殊前缀）
│   ├── base/
│   │   ├── nixos.nix
│   │   └── home.nix
│   └── security/
│       └── nixos.nix
├── desktop/          # 仅注入包含 "desktop" 角色的主机
│   ├── hyprland/
│   │   ├── nixos.nix
│   │   └── home.nix
│   └── fonts/
│       └── nixos.nix
├── server/           # 仅注入包含 "server" 角色的主机
│   └── nginx/
│       └── nixos.nix
└── development/      # 仅注入包含 "development" 角色的主机
    └── tools/
        ├── nixos.nix
        └── home.nix
```

## 过滤规则

| 模块路径 | 加载条件 |
| -------- | -------- |
| `modules/_common/**` | 始终注入 |
| `modules/<role>/**` | 主机 `roles` 包含 `<role>` |
| `modules/<role>/**/default.nix` | 始终注入（共享 option） |
| 未声明 `roles` 的主机 | 全量注入（向后兼容） |

注意：`default.nix` 永远注入，保证各角色的 option 声明在所有主机可见（`lib.mkEnableOption` 等不会因角色过滤而缺失）。

## 组合角色

多角色组合：

```nix
{
  roles = [
    "desktop"
    "development"
  ];
}
```

等价于同时注入 `_common`、`desktop`、`development` 三个目录下的模块。

## 角色与 option 的关系

角色只控制 **import**，不等同于 option 开关。推荐在模块内部仍使用 option 做细粒度控制：

```nix
# modules/desktop/hyprland/nixos.nix
{ config, lib, ... }:
{
  config = lib.mkIf config.cloud.hyprland.enable {
    # ...
  };
}
```

这样即使同属 `desktop` 角色，用户也可以通过 `cloud.hyprland.enable = false` 禁用单个功能。

## 调试模块加载

查看框架发现了哪些模块：

```bash
nix build .#checks.x86_64-linux.cloud-discovery && cat result | python3 -m json.tool
```

输出中 `modules` 字段列出所有已发现模块及其路径和角色归属。
