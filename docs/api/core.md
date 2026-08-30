# 核心 API

框架通过 flake 的 `lib` 输出暴露统一命名空间。用户 flake 中的完整入口是 `inputs.cloud.lib.mkFlake`。

## `mkFlake`

顶层 outputs 构造器，自动扫描目录并拼接全部 outputs：

```nix
inputs.cloud.lib.mkFlake {
  inherit inputs;
  root = ./.; # 可选；通常自动推导，封装调用时可显式指定
  systems = [ "x86_64-linux" "aarch64-linux" ];
  extraOutputs = { };
  extraSpecialArgs = { };
  extraModules = [ ];
  extraNixosModules = [ ];
  extraHomeModules = [ ];
  nixpkgsConfig = { allowUnfree = true; };
  extraOverlays = [ ];
  embedHomeManager = true;
  moduleRegistries = [ ];
}
```

| 参数 | 默认值 | 说明 |
| ---- | ------ | ---- |
| `inputs` | 必填 | 当前用户 flake 的全部 inputs |
| `root` | 自动推导 | 配置仓库根目录；自定义 helper 封装调用时可显式传入 `./.` |
| `systems` | `x86_64-linux`、`aarch64-linux` | per-system outputs 的目标架构 |
| `extraOutputs` | `{ }` | 与自动生成 outputs 深度合并 |
| `extraSpecialArgs` | `{ }` | 注入 NixOS、独立 HM 与嵌入式 HM |
| `extraModules` | `[ ]` | 同时追加到 NixOS 与 HM |
| `extraNixosModules` | `[ ]` | 仅追加到 NixOS |
| `extraHomeModules` | `[ ]` | 追加到独立与嵌入式 HM |
| `nixpkgsConfig` | `{ }` | 统一的 nixpkgs 配置，如 `allowUnfree` |
| `extraOverlays` | `[ ]` | 在自动发现 overlays 之后追加 |
| `embedHomeManager` | `true` | 是否把关联 home 嵌入 NixOS |
| `moduleRegistries` | `[ ]` | 按需并入外部模块注册表 |

`nixpkgsConfig`、自动发现的 overlays 和 `extraOverlays` 会统一应用到 NixOS、独立/嵌入式 home-manager、packages、checks、devShells、apps 与 formatter。

## `mkSystem`

`mkSystem` / `mkHome` 需要先通过 `mkLib { inherit inputs; }` 绑定当前用户 flake；它们不是框架 input 上的未绑定函数。

创建单个 `nixosConfigurations.<host>`：

```nix
outputs = inputs:
  let
    cloud = inputs.cloud.lib.mkLib { inherit inputs; };
  in
  {
    nixosConfigurations.nixos-desktop = cloud.mkSystem {
      host = "nixos-desktop";
      system = "x86_64-linux"; # null 时从 hosts/<host>.<system>/ 派生
      modules = [ ];
      extraModules = [ ];
      extraNixosModules = [ ];
      extraHomeModules = [ ];
      extraSpecialArgs = { };
      nixpkgsConfig = { };
      extraOverlays = [ ];
      embedHomeManager = true;
    };
  };
```

`extraHomeModules` 仅在嵌入关联 home 时使用。`embedHomeManager = false` 不影响独立 `homeConfigurations` 的生成。

## `mkHome`

创建单个 `homeConfigurations.<user>` 或 `homeConfigurations."<user>@<host>"`：

```nix
outputs = inputs:
  let
    cloud = inputs.cloud.lib.mkLib { inherit inputs; };
  in
  {
    homeConfigurations."rhencloud@nixos-desktop" = cloud.mkHome {
      user = "rhencloud";
      host = "nixos-desktop";  # null 表示全局 home
      system = "x86_64-linux"; # 仅全局 home 使用
      modules = [ ];
      extraModules = [ ];
      extraHomeModules = [ ];
      extraSpecialArgs = { };
      nixpkgsConfig = { };
      extraOverlays = [ ];
    };
  };
```

带 `host` 的 home 自动继承对应主机目录后缀中的架构。`mkFlake` 生成全局 home 时使用 `systems` 首项。

## `mkLib`

```nix
inputs.cloud.lib.mkLib { inherit inputs; }
```

返回已绑定当前 flake 的 `cloud` 命名空间。

## 自动发现函数

- `importModules dir`：返回扁平的 `{ nixos = [ ... ]; home = [ ... ]; }`。
- `groupModules dir`：按目录键返回分组模块。
- `flattenTree tree`：将嵌套属性集展开为点分键。

遍历结果按完整相对路径字典序排序。

## Patch helper

- `cloud.patches.local path`
- `cloud.patches.fromPR { fetchpatch; owner; repo; pr; hash; }`

## sops helper

- `cloud.sops.commonFile`
- `cloud.sops.hostFile host`
- `cloud.sops.defaultFile host`
- `cloud.sops.mkModule { sopsNixModule; host ? null; defaultSopsFile ? cloud.sops.defaultFile host; }`

sops helper 是显式助手：不会自动注入模块，也不会合并 common 与 host 文件。

## 分层入口

`mkFlake` 覆盖常规场景，`mkSystem` / `mkHome` 作为细粒度逃生舱。现有单字符串 `role` 仍兼容，新配置推荐使用顶层 `roles = [ ... ];`。
