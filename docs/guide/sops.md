# 密钥管理（sops）

框架提供显式的 sops-nix helper，但不硬编码 sops-nix input。

::: warning 文件不会自动合并

helper 不会组合 `secrets/common.yaml` 与 `secrets/hosts/<host>.yaml`。`defaultSopsFile` 只能选择一个默认文件，除非调用方显式覆盖。

:::

默认选择规则：

- `host = null` → `secrets/common.yaml`；
- `host = "<host>"` → `secrets/hosts/<host>.yaml`。

## 最小接入

```nix
# flake.nix inputs
sops-nix = {
  url = "github:Mic92/sops-nix";
  inputs.nixpkgs.follows = "nixpkgs";
};
```

```nix
# hosts/nixos-desktop.x86_64-linux/default.nix
{ cloud, inputs, ... }:
{
  imports = [
    (cloud.sops.mkModule {
      sopsNixModule = inputs.sops-nix.nixosModules.sops;
      host = "nixos-desktop";
    })
  ];
}
```

调用 `mkModule` 才会注入传入的 sops-nix 模块；框架不会仅因目录中存在密钥文件而自动注入。

## API

- `cloud.sops.commonFile`
- `cloud.sops.hostFile host`
- `cloud.sops.defaultFile host`
- `cloud.sops.mkModule { sopsNixModule; host ? null; defaultSopsFile ? cloud.sops.defaultFile host; }`

## 自定义默认文件

```nix
cloud.sops.mkModule {
  sopsNixModule = inputs.sops-nix.nixosModules.sops;
  defaultSopsFile = ./secrets/combined.yaml;
}
```

如果需要同时使用 common 与 host 文件，可在 sops-nix 配置中为不同 secret 显式设置各自的 `sopsFile`，或在仓库外部预先生成一个组合文件；框架不会隐式合并 YAML。
