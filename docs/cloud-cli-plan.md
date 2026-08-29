# Cloud CLI 实施计划（A 分支）

> 状态：待实施（计划先行）。本工具为**独立 Rust 仓库**，不落入 Cloud Nix Framework 本体。

## 定位

- **本质**：flake 输出路径的缩写层，把 `nixosConfigurations.<host>` / `homeConfigurations.<user>@<host>` / `packages.<system>.<name>` 等深层输出映射为短命令。
- **实现语言**：Rust（`Q27=B`，独立编译工具，`Q17=B`）。
- **依赖**：仅封装已有的 `nix` CLI（`nix flake init/show/run/develop`、colmena/deploy-rs），不引入 Nix 求值逻辑。

## 首版子命令（`Q33=A`）

| 子命令 | 封装目标 | 说明 |
| --- | --- | --- |
| `init` | `nix flake init --template` | repo 级用模板源（`Q18=D`/`Q22=C`）；file 级用 `--type`（`Q21=A` 骨架最小可跑：`enable` + `mkIf`） |
| `deploy` | colmena / deploy-rs | 薄封装，自动发现 `hostName`（`Q24=A`） |
| `run` | `nix run` | 封装（`Q25=A`） |
| `shell` | `nix develop` | 封装（`Q26=A`） |

## 解析与发现

- **定位 flake**（`Q28=A`）：从 cwd 向上查找 `flake.nix`，支持 `--flake` 覆盖。
- **枚举输出**（`Q29=A`）：`nix flake show --json` 解析 `nixosConfigurations` / `homeConfigurations` / `packages` 等。
- **候选类型优先级**（`Q30`）：每子命令维护一张「候选类型 → 优先级」表，按优先级取首个匹配。
- **system 默认**（`Q31=A`）：`system = nixpkgs#system`（通过 `nix eval nixpkgs#system` 取得）。
- **无匹配**（`Q32=A`）：报错并列出候选；歧义时按优先级取首并提示。

## 设计约束

- `init` 默认复用框架 `templates/default`（`Q23=A`）。
- 不重复框架逻辑：仅做路径缩写与子命令分发，所有实际构建交给 `nix` / 部署工具。
- 模块注册表（C 分支）已在框架内实现，CLI 无需感知。

## 待决 / 后续

- 仓库脚手架（Cargo.toml、cli 框架选型、参数解析库）。
- `Q30` 优先级表细化。
- 与 colmena / deploy-rs 的具体集成方式（flake 输出约定）。
