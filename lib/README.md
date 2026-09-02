# Snowveil - Library Structure

本目录包含框架的所有库代码。

## 当前结构

### 核心模块（已稳定）

- **default.nix** - 主入口点，导出 `mkFlake`, `mkSystem`, `mkHome`, `mkLib` 等公共 API
- **discover.nix** - 目录自动发现系统（hosts, homes, packages, overlays 等）
- **host.nix** - 主机元数据处理和角色过滤
- **sops.nix** - SOPS 密钥管理帮助函数
- **patches.nix** - 补丁应用工具函数
- **fs.nix** - 文件系统树遍历工具

### 内部模块（框架开发用）

- **internal/options.nix** - 框架内置的 NixOS/Home Manager 选项定义
- **internal/utils.nix** - 通用工具函数（选项渲染等）

## 长期重构计划

本库正在按如下结构进行分层重构（预计 0.4.x 版本）：

```
lib/
├── default.nix              # 公共 API 导出
├── internal/                # 框架内部实现
│   ├── options.nix
│   ├── utils.nix
│   ├── bind.nix            # (未来) 主装配函数
│   └── ...
├── api/                      # (未来) 公共 API 函数
│   ├── mkFlake.nix
│   ├── mkSystem.nix
│   ├── mkHome.nix
│   └── mkLib.nix
├── discovery/                # (未来) 发现逻辑细分
│   ├── hosts.nix
│   ├── homes.nix
│   ├── modules.nix
│   └── ...
├── metadata/                 # (未来) 元数据处理
│   ├── host.nix
│   ├── validation.nix
│   └── roles.nix
├── evaluation/               # (未来) 求值逻辑
│   ├── nixpkgs.nix
│   ├── specialArgs.nix
│   └── modules.nix
└── outputs/                  # (未来) 输出生成
    ├── packages.nix
    ├── apps.nix
    ├── checks.nix
    └── ...

（以及 overlays.nix 等独立模块）
```

## 注意

- 当前版本（0.3.x）中，大部分逻辑仍集中在 `default.nix` 的 `bind` 函数中
- 重构是**渐进式**的，不会立即改变公共 API
- 所有公共函数（mkFlake, mkSystem 等）保持兼容性
- 重构的目标是提高代码可维护性和可读性
