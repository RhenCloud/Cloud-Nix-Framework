# AGENTS.md

面向 AI 编码代理（及贡献者）的框架自身开发约定。此仓库是 **Cloud Nix Framework** 的库本体，不是用户配置仓库。

## 项目概述

Cloud Nix Framework 是一个基于 Nix Flakes 的配置框架，用「目录约定 + 自动发现」替代样板代码，聚焦 NixOS + home-manager 双对象配置。设计理念调和自 flake.parts（模块化）、snowfallorg/lib（统一配置/分类发现）、flake-fhs（目录即 flake）。框架自身**零 flake-utils / flake.parts 运行时依赖**，纯 `nixpkgs.lib` 实现。

## 仓库结构

```
.
├── flake.nix                 # 入口：暴露 lib / templates / checks
├── lib/                      # 框架库源码（cloud 命名空间）
│   ├── default.nix           #   mkFlake / mkSystem / mkHome / mkLib ...
│   ├── fs.nix                #   文件系统树遍历（自动发现）
│   └── patches.nix           #   cloud.patches.local / fromPR
├── templates/                # flake 模板（nix flake init --template）
│   └── default/
├── examples/                 # 可运行的最小示例
├── checks/                   # flake check 自检
├── modules/                  # 用户模块（自动发现，可选）
└── docs/                     # VitePress 文档（npm 管理，见下）
```

## 命令约定

| 用途 | 命令 |
| ---- | ---- |
| 格式化 | `nixfmt` |
| 静态检查（lint） | `statix check` |
| 死代码清理 | `deadnix -l -L -_` |
| 仓库自检 | `nix flake check` |
| 进入开发环境 | `nix develop` |

提交前依次运行：`nixfmt` → `deadnix -l -L -_` → `statix check` → `nix flake check`。

## 编码约定

- **语言**：代码注释与用户交互字符串使用**中文（简体）**；提交信息使用英文，简洁准确。
- **注释**：默认**不添加**注释，除非逻辑非显而易见。
- **工具链**：依赖通过 Nix 管理，不引入 npm/pip/cargo 等外部安装步骤；开发依赖放 `devShell`。
- **格式**：`nixfmt` 风格，标签属性（attrset）优先，避免无谓的嵌套 `with`。

## 文档与风格规范

- TypeScript 风格：https://docs.worldexecute.me/development/ts-style/
- Markdown 风格：https://docs.worldexecute.me/development/markdown/
- 站点文档放 `docs/`，用 VitePress + npm 管理（devShell 已提供 `nodejs`）：`cd docs && npm run docs:dev`（预览）/ `docs:build`（构建）。

## 核心 API 契约

框架对外暴露的命名空间为 `cloud`，这是公共接口，**不允许破坏性变更**（改动需在 README「核心 API」章节同步）：

- `mkFlake { inherit inputs; systems ? [ ... ]; extraOutputs ? { }; extraSpecialArgs ? { }; }` → 顶层 outputs 构造器
- `mkSystem { host; system ? null; modules ? []; extraSpecialArgs ? {}; }` → `nixosConfigurations.<host>`
- `mkHome { user; host ? null; system ? null; modules ? []; extraSpecialArgs ? {}; }` → `homeConfigurations.<user>` 或 `"<user>@<host>"`
- `mkLib { inherit inputs; }` → 返回 `cloud` 命名空间
- `importModules` / `flattenTree` / `groupModules` → 目录自动发现工具函数
- `cloud.patches.local` / `cloud.patches.fromPR` → patch helper

新增公共函数时，须在 `lib/default.nix` 导出，并在 README「核心 API」章节补充说明。

## 目录自动发现规则

- `hosts/` 主机目录**必须**带 `.<system>` 后缀（`hosts/<name>.<system>/default.nix`），不猜测默认架构；key 为去后缀的 `<name>`。
- `homes/<user>/<host>.nix` 声明该 home 关联到某主机（自动推导 `nixosConfigurations.<host>` 的 `cloud.users`，无需在 host 中手写）；`homes/<user>/default.nix` 为用户共享 home。
- `modules/` 单树递归收集四个 magic 文件：`options.nix`（接口声明，始终注入）、`default.nix`（中性共享实现）、`nixos.nix`（NixOS 专属实现）、`home.nix`（home-manager 专属实现）。
  - NixOS side load order：`options.nix` → `default.nix` → `nixos.nix`
  - home-manager side load order：`options.nix` → `default.nix` → `home.nix`
  - This ensures interface declaration loads first, separates implementation, and prevents accidentally importing unrelated code.
- 遍历结果按**完整相对路径字典序**排序，保证模块合并顺序稳定、可复现（构建不可依赖文件系统读取次序）。
- 模块名 = 相对路径去掉 magic 文件名、以 `.` 连接（`modules/desktop/hyprland/nixos.nix` → `desktop.hyprland`）。
- 空目录、无 magic 文件的叶子目录会被忽略；category 层为可选组织方式，发现逻辑容忍任意深度。

## 模块/示例/模板约定

- 用户模块按目录自动发现：放 `modules/`。模块结构遵循分层约定：
  - `options.nix`（可选但推荐）：声明 `options.cloud.<name>.*` 接口，始终在两侧注入
  - `default.nix`（可选）：中性实现，两侧都会使用
  - `nixos.nix`（可选）：NixOS 专属实现
  - `home.nix`（可选）：home-manager 专属实现
  - 框架在 `mkFlake` 中自动按加载顺序分拣注入，无需手写 `import`。框架本身不内置默认模块。
- 新增示例：放 `examples/<name>`，目录结构与用户仓库一致（`hosts/`、`homes/`、`modules/`、`overlays/` 等），确保 `nix flake check` 能验证。
- 新增模板：放 `templates/<name>`，模板应是极简可跑的最小结构。


## 验证要求

任何改动（新增函数、修改自动发现逻辑、新增模板）都必须通过 `nix flake check` 验证；如有示例，需同时在示例上跑通构建。不要提交未格式化或 `statix` 报错的文件。

## 提交约定

- 提交信息英文、简洁、准确（如 `feat: add mkHome scaffolding function`）。
- 不主动 commit/push，除非用户明确要求。