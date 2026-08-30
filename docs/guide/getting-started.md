# 快速开始

Cloud Nix Framework 用「约定代替样板」，让多主机、多用户的 NixOS + home-manager 配置仓库结构清晰、可复用。

## 初始化模板

```bash
nix flake init --template github:RhenCloud/Cloud-Nix-Framework
```

## flake.nix 最小示例

```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    cloud = {
      url = "github:RhenCloud/Cloud-Nix-Framework";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.home-manager.follows = "home-manager";
    };
  };

  outputs = inputs: inputs.cloud.lib.mkFlake { inherit inputs; };
}
```

入口位于框架 flake 的 `lib` output 下，因此应使用 `inputs.cloud.lib.mkFlake`，而不是 `inputs.cloud.mkFlake`。

仅凭这一段，`hosts/`、`homes/`、`modules/`、`packages/`、`overlays/`、`apps/`、`formatter/`、`deploy/`、`lib/`、`shells/`、`checks/` 下的内容就会被自动解析。

## 常用全局配置

```nix
outputs = inputs:
  inputs.cloud.lib.mkFlake {
    inherit inputs;

    nixpkgsConfig = {
      allowUnfree = true;
      permittedInsecurePackages = [ ];
    };

    extraOverlays = [ ];
    extraSpecialArgs = { };

    # 默认嵌入，仅为指定主机关闭。
    embedHomeManager = {
      default = true;
      hosts.yc-hk-1 = false;
    };

    # 可按主机关闭 useGlobalPkgs，兼容需要自行添加 HM overlay 的模块。
    homeManagerUseGlobalPkgs = {
      default = true;
      hosts.nixos-desktop = false;
    };

    disabledOutputs = [ "checks.expensive" ];
  };
```

自动发现的 overlays、`extraOverlays` 与 `nixpkgsConfig` 会统一作用于 NixOS、独立/嵌入式 home-manager 以及所有 per-system outputs。关闭 `homeManagerUseGlobalPkgs` 时，这些配置会注入 HM 自己的 nixpkgs，同时允许 HM 模块追加 overlay。

推荐在每台主机的 `meta.nix` 声明角色和主机级策略：

```nix
# hosts/nixos-desktop.x86_64-linux/meta.nix
{
  roles = [
    "desktop"
    "development"
  ];

  home.useGlobalPkgs = false;
}
```

## 常见用法

```bash
# 构建并切换主机
sudo nixos-rebuild switch --flake .#nixos-desktop

# 切换用户环境（全局 home）
home-manager switch --flake .#rhencloud

# 切换某主机专属 home
home-manager switch --flake .#rhencloud@nixos-desktop

# 运行 app
nix run .#hello

# 构建隔离检查（CI）
nix flake check path:. --show-trace
```
