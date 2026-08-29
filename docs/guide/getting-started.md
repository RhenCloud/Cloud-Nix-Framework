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
    home-manager.url = "github:nix-community/home-manager";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";
    cloud.url = "github:RhenCloud/Cloud-Nix-Framework";
    cloud.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = inputs: inputs.cloud.mkFlake {
    inherit inputs;
  };
}
```

仅凭这一段，`hosts/`、`homes/`、`modules/`、`packages/`、`overlays/`、`lib/`、`shells/`、`checks/` 下的内容就会被自动解析成完整配置。

## 常见用法

```bash
# 构建并切换主机
sudo nixos-rebuild switch --flake .#nixos-desktop

# 切换用户环境（全局 home）
home-manager switch --flake .#rhencloud

# 切换某主机专属 home
home-manager switch --flake .#rhencloud@nixos-desktop

# 构建隔离检查（CI）
nix flake check
```