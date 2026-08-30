# 核心 API

框架通过 flake 的 `lib` output 暴露统一命名空间。用户 flake 中的完整入口是 `inputs.cloud.lib.mkFlake`。

## `mkFlake`

顶层 outputs 构造器，自动扫描目录并拼接全部 outputs：

```nix
inputs.cloud.lib.mkFlake {
  inherit inputs;
  root = ./.; # 可选；通常自动推导
  systems = [ "x86_64-linux" "aarch64-linux" ];
  extraOutputs = { };
  extraSpecialArgs = { };
  extraModules = [ ];
  extraNixosModules = [ ];
  extraHomeModules = [ ];
  nixpkgsConfig = { allowUnfree = true; };
  extraOverlays = [ ];
  embedHomeManager = true;
  homeManagerUseGlobalPkgs = true;
  disabledOutputs = [ ];
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
| `embedHomeManager` | `true` | 是否把关联 home 嵌入 NixOS；支持全局值、函数和 per-host 属性集 |
| `homeManagerUseGlobalPkgs` | `true` | 嵌入式 HM 是否复用 NixOS `pkgs`；支持按主机配置 |
| `disabledOutputs` | `[ ]` | 在求值文件前禁用自动发现的 output |
| `moduleRegistries` | `[ ]` | 按需并入外部模块注册表 |

`embedHomeManager` 与 `homeManagerUseGlobalPkgs` 都支持三种形式：

```nix
# 全局值
embedHomeManager = false;

# 函数
embedHomeManager = host: host != "yc-hk-1";

# 带默认值的 per-host 策略
embedHomeManager = {
  default = true;
  hosts.yc-hk-1 = false;
};
```

主机的 `meta.nix` 可以覆盖全局策略：

```nix
# hosts/yc-hk-1.x86_64-linux/meta.nix
{
  roles = [ "server" ];

  homeManager = {
    embed = false;
    useGlobalPkgs = false;
  };
}
```

也可在 `meta.nix` 顶层使用等价字段：

```nix
{
  role = "server";
  embedHomeManager = false;
  homeManagerUseGlobalPkgs = false;
}
```

主机元数据优先于全局策略。关闭 `useGlobalPkgs` 时，框架会把自动发现的 overlays、`extraOverlays` 与 `nixpkgsConfig` 注入该主机的 HM nixpkgs，使 HM 模块仍可追加自己的 overlays。这适合 Stylix 等需要在 HM 侧设置 overlay 的模块。

`disabledOutputs` 推荐使用完整 output 标识：

```nix
disabledOutputs = [
  "checks.expensive"
  "checks.aarch64-linux.broken-on-aarch64"
  "packages.some-package"
  "apps.debug"
  "formatter"
  "deploy"
];
```

也可写成分类属性集：

```nix
disabledOutputs = {
  checks = [ "expensive" ];
  packages = [ "some-package" ];
};
```

## `mkSystem`

`mkSystem` / `mkHome` 需要先通过 `mkLib { inherit inputs; }` 绑定当前用户 flake；它们不是框架 input 上的未绑定函数。

```nix
outputs = inputs:
  let
    cloud = inputs.cloud.lib.mkLib { inherit inputs; };
  in
  {
    nixosConfigurations.nixos-desktop = cloud.mkSystem {
      host = "nixos-desktop";
      system = "x86_64-linux";
      modules = [ ];
      extraModules = [ ];
      extraNixosModules = [ ];
      extraHomeModules = [ ];
      extraSpecialArgs = { };
      nixpkgsConfig = { };
      extraOverlays = [ ];
      embedHomeManager = true;
      homeManagerUseGlobalPkgs = true;
    };
  };
```

`extraHomeModules` 仅在嵌入关联 home 时使用。关闭嵌入不影响独立 `homeConfigurations` 的生成。

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
      host = "nixos-desktop";
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

## SOPS helper

- `cloud.sops.commonFile`
- `cloud.sops.hostFile host`
- `cloud.sops.defaultFile host`
- `cloud.sops.secret { source = "common" | "host"; host ? null; name ? null; }`
- `cloud.sops.mkModule { sopsNixModule; host ? null; defaultSopsFile ? cloud.sops.defaultFile host; }`

`secret` 传入 `name` 时返回 `{ sops.secrets.<name>.sopsFile = ...; }` 模块片段；省略 `name` 时返回 `{ sopsFile = ...; }`，便于直接赋给已有 secret。`sops` helper 不会自动注入模块，也不会合并 common 与 host 文件。

## 分层入口

`mkFlake` 覆盖常规场景，`mkSystem` / `mkHome` 作为细粒度逃生舱。新配置应在 `hosts/<name>.<system>/meta.nix` 声明角色和 Home Manager 策略；旧的 host module 顶层 `role` / `roles` 等元数据仍兼容。
