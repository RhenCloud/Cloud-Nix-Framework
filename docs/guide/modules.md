# 模块写作

模块采用**单树 + 文件名分拣**，一个程序只对应一个目录，消除 NixOS 与 home-manager 两棵平行树的重复。

## 三个 magic 文件

- `default.nix`：**中性模块**，声明该程序共享的 option 接口（`options.cloud.<name>.*`），不引用 `services.*` 或 `programs.*`。
- `nixos.nix`：NixOS 专属逻辑，读取 `config.cloud.<name>.*` 挂服务。
- `home.nix`：home-manager 专属逻辑，读取同一 option 挂 dotfile。

```nix
# modules/desktop/hyprland/default.nix
{ config, lib, ... }: {
  options.cloud.hyprland = {
    enable = lib.mkEnableOption "Hyprland";
  };
}
```

```nix
# modules/desktop/hyprland/nixos.nix
{ config, ... }: {
  config = {
    # 依据 config.cloud.hyprland.enable 决定系统级配置
  };
}
```

```nix
# modules/desktop/hyprland/home.nix
{ config, ... }: {
  config = {
    # 依据相同 config.cloud.hyprland.enable 决定用户级配置
  };
}
```

## 模块分拣规则

- NixOS 侧 = 全部 `default.nix` + `nixos.nix`。
- home-manager 侧 = 全部 `default.nix` + `home.nix`。
- 模块名由相对路径去掉 magic 文件名、以 `.` 连接派生（`modules/desktop/hyprland/nixos.nix` → `desktop.hyprland`），用于错误定位与去重。
- category 层（`modules/<category>/<name>/`）为可选的纯组织方式，发现逻辑容忍任意深度。
- 遍历按完整相对路径字典序排序，保证模块合并顺序稳定、可复现。
- 空目录、无 magic 文件的叶子目录会被忽略。

## 注入的模块参数

所有模块均自动获得：

- `inputs`：全部 flake inputs
- `channels`：单 `nixpkgs` 预留解析入口
- `self`：本 flake（用于 `self.outPath` 定位仓库根目录）
- NixOS / home-manager 原生参数（`config` / `pkgs` / `lib` / `options` 等）