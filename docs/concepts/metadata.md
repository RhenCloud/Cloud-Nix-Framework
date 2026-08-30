# 元数据系统（meta.nix）

## 原则

框架元数据与 NixOS 配置严格分离：

| 文件 | 作用 | 求值阶段 |
| ---- | ---- | -------- |
| `meta.nix` | 框架元数据（角色、策略） | 发现阶段，纯属性集 |
| `default.nix` | NixOS 模块配置 | NixOS module system |

`meta.nix` 不是 NixOS 模块，不接受 `config`、`pkgs`、`lib` 等模块参数。

## hosts meta.nix 完整字段

```nix
# hosts/<name>.<system>/meta.nix
{
  # 若目录名无 .<system> 后缀时必填
  system = "x86_64-linux";

  # 角色：过滤 modules/ 下哪些目录被注入该主机
  roles = [ "desktop" "development" ];
  # role = "desktop";  # 单值别名

  # HM 嵌入策略（null 表示继承 mkFlake 全局值）
  home.embed = true;
  home.useGlobalPkgs = true;

  # 镜像格式（在发现阶段读取，避免强制求值整个 config）
  images.formats = [ "iso" ];
}
```

**已弃用字段**（仍兼容，但会输出 trace 警告）：

- `embedHomeManager` → 使用 `home.embed`
- `homeManagerUseGlobalPkgs` → 使用 `home.useGlobalPkgs`
- `homeManager.embed` → 使用 `home.embed`
- `homeManager.useGlobalPkgs` → 使用 `home.useGlobalPkgs`
- `role`（单值）→ 仍可使用，与 `roles` 互为别名

## 优先级

```
主机 meta.nix 字段  >  mkFlake 全局参数  >  框架硬编码默认值
```

## packages / checks / apps meta.nix

```nix
# packages/<name>/meta.nix 或 checks/<name>/meta.nix
{
  enable = true;          # false 时不生成该 output
  systems = [ "x86_64-linux" ];  # 限制架构（null 表示所有 systems）
}
```

## homes meta.nix

homes 目录当前不读取 `meta.nix`；位置保留供未来使用（如多架构全局 home 的 system 声明）。

## 限制

- `meta.nix` 必须直接返回属性集，不能是函数。
- 违反此约定在发现阶段 `throw` 报错。
- `meta.nix` 中不能引用 `pkgs`、`config` 等运行时值。
