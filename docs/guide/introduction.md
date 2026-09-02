# 介绍

Snowveil 是一个基于 Nix Flakes 的声明式配置框架，融合三个优秀项目的设计理念：

| 参考项目 | 借鉴的设计 |
| -------- | ---------- |
| [flake.parts](https://flake.parts/) | 模块化、声明式、可组合的配置方式 |
| [snowfallorg/lib](https://github.com/snowfallorg/lib) | 统一管理系统 / 模块 / 主机配置，分类自动发现 |
| [flake-fhs](https://github.com/luochen1990/flake-fhs) | 「目录即 Flake」，按约定组织目录自动生成 outputs |

核心目标：**用约定代替样板（convention over configuration）**，让多主机、多用户的 NixOS + home-manager 配置仓库结构清晰、可复用、易上手。

## 设计理念

- **约定优于配置**：目录层级即配置意图，无需手写 import 列表与 output 拼接。
- **纯 `nixpkgs.lib`**：框架自身零 `flake-utils` / `flake.parts` 运行时依赖，`forAllSystems` 与文件系统遍历自实现。
- **双对象**：同时覆盖 NixOS（系统级）与 home-manager（用户级），且二者共享同一模块来源，避免重复。
- **分层入口**：`mkFlake` 覆盖常规场景，`mkSystem` / `mkHome` 作为细粒度逃生舱，兼顾零样板与例外处理。
- **无侵入、渐进式**：作为独立 flake input 引入，可平滑迁移既有配置。

## 与其他框架对比

| | Snowveil | snowfallorg/lib | flake-fhs | flake.parts | nixos-unified | den |
| ---- | ---- | ---- | ---- | ---- | ---- | ---- |
| 定位 | 约定式配置框架 | 统一配置库 | 目录映射 outputs | 通用 flake 模块系统 | 三平台统一配置模块 | 面向切面、功能优先 |
| 组织方式 | 目录约定 + 单树分拣 | 目录约定 + 分类 | 目录树即 flake | flake 模块系统 | flake-parts 模块 + autowiring | aspect 函数 + policy |
| NixOS + home-manager | 是（同源双轨） | 是 | 是 | 可组合 | 是（+nix-darwin） | 是（+darwin + 自定义 class） |
| 运行时依赖 | 纯 nixpkgs.lib | flake-utils-plus | 自研 | 自研模块系统 | flake-parts | 零依赖（可选集成） |
| 目录自动发现 | 是 | 是 | 是 | 否 | 可选 autowiring | 否 |

- [nixos-unified](https://nixos-unified.org/)：flake-parts 模块，用统一的 `.#activate` app 一键激活/部署（含远程 SSH），统一 NixOS + nix-darwin + home-manager；可选 autowiring 扫描目录自动挂接 outputs。
- [den](https://den.denful.dev)：面向切面（aspect-oriented）、功能优先。核心抽象是 aspect —— 一个以 context（`{ host, user }`）为参数的函数，返回多个 Nix class（nixos/darwin/homeManager 等）的配置，用 policy 描述实体拓扑；零依赖，支持 flake 与非 flake。