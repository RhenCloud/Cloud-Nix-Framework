# 模块写作

模块采用**单树 + 文件名分拣**，一个功能只对应一个目录，消除 NixOS 与 home-manager 两棵平行树的重复。

## 三个 magic 文件

- `default.nix`：中性模块，通常声明共享 option 接口，不引用单侧专属选项。
- `nixos.nix`：NixOS 专属逻辑。
- `home.nix`：home-manager 专属逻辑。

```nix
# modules/desktop/hyprland/default.nix
{ lib, ... }:
{
  options.cloud.hyprland.enable = lib.mkEnableOption "Hyprland";
}
```

```nix
# modules/desktop/hyprland/nixos.nix
{ config, lib, ... }:
{
  config = lib.mkIf config.cloud.hyprland.enable {
    # 系统级配置
  };
}
```

```nix
# modules/desktop/hyprland/home.nix
{ config, lib, ... }:
{
  config = lib.mkIf config.cloud.hyprland.enable {
    # 用户级配置
  };
}
```

## 模块分拣规则

- NixOS 侧 = 全部 `default.nix` + `nixos.nix`。
- home-manager 侧 = 全部 `default.nix` + `home.nix`。
- 目录键由相对目录路径以 `.` 连接派生，例如 `modules/desktop/hyprland/` → `desktop.hyprland`。
- `nixosModules."desktop.hyprland"` 与 `homeModules."desktop.hyprland"` 的值是 `{ imports = [ ... ]; }`，不会暴露 `nixos.nix` 等 magic 文件名。
- 遍历按完整相对路径字典序排序，保证合并顺序稳定、可复现。
- 空目录和没有 magic 文件的叶子目录会被忽略。
- 不同路径映射到同一目录键时会在求值期报错。

## 组合角色

推荐在主机的静态元数据文件中声明角色：

```nix
# hosts/nixos-desktop/meta.nix
{
  system = "x86_64-linux";
  roles = [
    "desktop"
    "development"
  ];
}
```

过滤规则：

- `modules/desktop/**/nixos.nix` 和 `home.nix` 仅注入包含 `desktop` 角色的主机及其关联 home。
- `modules/development/**` 可与 desktop 同时注入。
- `modules/_common/**` 始终注入。
- 所有 `default.nix` 始终注入，保证共享 option 可见。
- 未声明 `roles` / `role` 时全量注入，保持向后兼容。

`meta.nix` 必须直接返回属性集，因此角色发现不会预执行函数式 host module。`hosts/<name>.<system>/default.nix` 只交给 NixOS module system，可以在模块外层使用真实 `config`。

旧配置仍可在 host module 顶层使用 `role = "desktop"` 或 `roles = [ ... ]`。该兼容路径需要用占位参数探测旧式元数据；若模块外层依赖真实 `config`，请迁移到 `meta.nix`。框架交给 NixOS 前会剥离旧式元数据字段。

## 注入的模块参数

所有 NixOS、独立 home-manager 与嵌入式 home-manager 模块均自动获得：

- `inputs`：全部 flake inputs；
- `channels`：当前 `nixpkgs` 的预留解析入口；
- `self`：当前用户 flake；
- `cloud`：`patches`、`sops`、`version` 等精简框架 helper；
- `nixos.specialArgs` 或 `home.specialArgs` 中对应模块系统的自定义参数；
- 模块系统原生参数，如 `config`、`pkgs`、`lib`、`options`。

嵌入式 home-manager 的自定义参数写入 `home-manager.extraSpecialArgs`，与独立 HM 行为一致。

## 额外模块

- `nixos.modules`：仅进入 NixOS。
- `home.modules`：进入独立与嵌入式 Home Manager。
- 两侧共享的模块应显式加入两个列表。旧的 `extraModules`、`extraNixosModules` 与 `extraHomeModules` 仍兼容，但已弃用。

## 公共模块与嵌入式 home-manager 的注意事项

`modules/_common/` 下的 `nixos.nix` 文件会注入**所有** NixOS 主机，包括禁用了 HM 嵌入（`home.embed = false`）的主机。

**不要**在公共 `nixos.nix` 模块中直接引用 `home-manager.*` option（如 `home-manager.backupFileExtension`、`home-manager.users` 等）——这些 option 由 home-manager NixOS 模块提供，仅当该主机启用了 HM 嵌入时才存在。在禁用嵌入的主机上求值会报"undefined option"错误。

### 正确做法：使用 `cloud.homeManager.backupFileExtension`

框架在所有 NixOS 主机上声明了 `cloud.homeManager.backupFileExtension`，无论嵌入状态。框架在启用嵌入时自动将其透传到 `home-manager.backupFileExtension`：

```nix
# modules/_common/hm-config/nixos.nix — 所有主机均可使用，无需条件判断
{ ... }:
{
  cloud.homeManager.backupFileExtension = "backup";
}
```

### 如果必须条件性引用 `home-manager.*`

若需要访问 `home-manager.*` 命名空间下的其他 option，用 `lib.mkIf` 配合 `config.cloud.users != []` 或专属模块进行保护：

```nix
{ config, lib, ... }:
{
  # 仅当此主机有关联 home 用户时才设置
  home-manager.useUserPackages = lib.mkIf (config.cloud.users != [ ]) true;
}
```

但更推荐将此类配置放到**按角色过滤的 `nixos.nix`** 而非 `_common/`，避免在无 HM 主机上意外报错。
