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
# hosts/nixos-desktop/default.nix
{ snowveil, inputs, ... }:
{
  imports = [
    (snowveil.sops.mkModule {
      sopsNixModule = inputs.sops-nix.nixosModules.sops;
      host = "nixos-desktop";
    })
  ];
}
```

调用 `mkModule` 才会注入传入的 sops-nix 模块；框架不会仅因目录中存在密钥文件而自动注入。

## 同时引用 common 与 host 文件

### 明确指定 host

```nix
{ snowveil, ... }:
{
  imports = [
    (snowveil.sops.secret {
      source = "common";
      name = "password-hash";
    })

    (snowveil.sops.secret {
      source = "host";
      host = "nixos-desktop";
      name = "mihomo-proxies";
    })
  ];
}
```

### 自动推导当前主机名（推荐）

`source = "host"` 省略 `host` 参数时，helper 返回一个 NixOS module，在求值阶段从 `config.networking.hostName` 自动推导路径。适合多主机共用同名 secret、各自对应 `secrets/hosts/<host>.yaml` 的场景：

```nix
{ snowveil, ... }:
{
  imports = [
    # 自动使用 config.networking.hostName 推导 secrets/hosts/<host>.yaml
    (snowveil.sops.secret {
      source = "host";
      name = "mihomo-proxies";
    })
  ];
}
```

::: tip

自动推导依赖 `networking.hostName` 在求值时已确定。若主机模块通过其他模块动态设置 `hostName`，建议显式传入 `host` 参数。

:::

需要普通 option 属性集而不是 module 时，可显式传入当前 `config`：

```nix
{ snowveil, config, ... }:
{
  sops.secrets.api-token =
    snowveil.sops.secret {
      source = "host";
      inherit config;
    }
    // {
      owner = "root";
      mode = "0400";
    };
}
```

`host` 与 `config` 不能同时传入。

在 common、显式 `host` 或显式 `config` 模式下省略 `name` 时，helper 返回单个 `sops.secrets.<name>` 所需的 option 属性集（不是 module），可继续与其他选项合并：

```nix
sops.secrets.password-hash =
  snowveil.sops.secret {
    source = "common";
  }
  // {
    neededForUsers = true;
  };
```

## API

- `snowveil.sops.commonFile`：`<root>/secrets/common.yaml` 路径
- `snowveil.sops.hostFile host`：`<root>/secrets/hosts/<host>.yaml` 路径
- `snowveil.sops.defaultFile host`：`host == null` 时取 `commonFile`，否则取 `hostFile host`
- `snowveil.sops.secret { source; host?; config?; name?; }`：
  - `source = "common"` → 返回 `{ sopsFile = ...; }` 或带 `name` 时返回 module/attrset
  - `source = "host"; host = "foo"` → 返回明确路径的属性集/module
  - `source = "host"; config = config` → 返回可直接合并的普通属性集
  - `source = "host"`（省略 `host` 和 `config`）→ 返回 NixOS module，求值时从 `config.networking.hostName` 推导
- `snowveil.sops.mkModule { sopsNixModule; host?; defaultSopsFile?; }`

## 自定义默认文件

```nix
snowveil.sops.mkModule {
  sopsNixModule = inputs.sops-nix.nixosModules.sops;
  defaultSopsFile = ./secrets/combined.yaml;
}
```

如果需要真正合并 common 与 host 内容，应在仓库外部预先生成组合文件；框架不会隐式合并 YAML。
