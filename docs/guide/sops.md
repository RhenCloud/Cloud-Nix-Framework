# 密钥管理（SOPS）

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

## 同时引用 common 与 host 文件

`cloud.sops.secret` 传入 `name` 时返回可直接导入的模块片段：

```nix
{ cloud, ... }:
{
  imports = [
    (cloud.sops.secret {
      source = "common";
      name = "password-hash";
    })

    (cloud.sops.secret {
      source = "host";
      host = "nixos-desktop";
      name = "mihomo-proxies";
    })
  ];
}
```

省略 `name` 时，helper 返回单个 `sops.secrets.<name>` 所需的 option 属性集。它只是选择路径，不会合并 YAML；返回值可继续与其他 secret 选项合并：

```nix
sops.secrets.password-hash =
  cloud.sops.secret {
    source = "common";
  }
  // {
    neededForUsers = true;
  };
```

## API

- `cloud.sops.commonFile`
- `cloud.sops.hostFile host`
- `cloud.sops.defaultFile host`
- `cloud.sops.secret { source = "common" | "host"; host ? null; name ? null; }`
- `cloud.sops.mkModule { sopsNixModule; host ? null; defaultSopsFile ? cloud.sops.defaultFile host; }`

## 自定义默认文件

```nix
cloud.sops.mkModule {
  sopsNixModule = inputs.sops-nix.nixosModules.sops;
  defaultSopsFile = ./secrets/combined.yaml;
}
```

如果需要真正合并 common 与 host 内容，应在仓库外部预先生成组合文件；框架不会隐式合并 YAML。
