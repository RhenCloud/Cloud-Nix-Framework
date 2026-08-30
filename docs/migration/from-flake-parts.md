# 从 flake.parts 迁移

## 相似点

- 均支持模块化组织 flake outputs
- 均支持 per-system outputs

## 主要差异

| | flake.parts | Cloud Nix Framework |
| ---- | ---- | ---- |
| 范式 | 显式模块组合 | 目录约定自动发现 |
| 扩展方式 | flakeModule | 约定目录 + extraOutputs |
| 目录发现 | 可选（autowiring） | 核心特性 |
| NixOS + HM 集成 | 需要组合模块 | 内置 |

## 何时选择 CNF

- 配置仓库以 NixOS + home-manager 为主
- 希望目录结构即配置意图，减少样板代码
- 不需要 flake.parts 插件生态

## 何时保留 flake.parts

- 需要大量非 NixOS 的 flake outputs（Rust crate、Go module 等）
- 已有大量 flakeModule 投资
- 团队熟悉 flake.parts 模块系统

## 混合使用

CNF 可以通过 `extraOutputs` 与 flake.parts 产出并存，无需完整迁移：

```nix
outputs = inputs:
  inputs.cloud.lib.mkFlake {
    inherit inputs;
    extraOutputs = {
      # 从 flake.parts 迁移过来的其他 outputs
    };
  };
```

## perSystem 对应

flake.parts 的 `perSystem` 在 CNF 中对应 `packages/`、`checks/`、`apps/`、`shells/`、`formatter/` 等目录约定。框架内部使用 `lib.genAttrs systems` 实现 per-system 展开。
