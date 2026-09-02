# 从普通 flake 迁移

## 迁移步骤

### 1. 添加 flake input

```nix
# flake.nix
inputs = {
  snowveil = {
    url = "github:SnowveilOrg/Snowveil";
    inputs.nixpkgs.follows = "nixpkgs";
    inputs.home-manager.follows = "home-manager";  # 若使用 HM
  };
};
```

### 2. 替换 outputs 函数

**之前**：

```nix
outputs = { self, nixpkgs, home-manager, ... }@inputs: {
  nixosConfigurations.nixos-desktop = nixpkgs.lib.nixosSystem {
    system = "x86_64-linux";
    modules = [ ./hosts/nixos-desktop/configuration.nix ];
    specialArgs = { inherit inputs; };
  };
};
```

**之后**：

```nix
outputs = inputs: inputs.snowveil.lib.mkFlake { inherit inputs; };
```

### 3. 重组目录结构

将主机配置移到框架约定路径：

```bash
# 从
hosts/nixos-desktop/configuration.nix

# 到
hosts/nixos-desktop.x86_64-linux/default.nix
```

`system` 信息从目录后缀提取，不再需要在 `nixosSystem` 中显式声明。

### 4. 迁移 home-manager

```bash
# 从（嵌入 NixOS）
hosts/nixos-desktop/home.nix（在 NixOS 配置内引用）

# 到
homes/rhencloud/nixos-desktop.nix（独立文件，框架自动嵌入）
```

### 5. 迁移模块

```bash
# 从
modules/desktop.nix

# 到
modules/desktop/nixos.nix  # 或 modules/desktop/default.nix
```

### 6. 迁移 packages/overlays

```bash
# packages 位置不变，框架自动发现
packages/hello/default.nix  →  packages.x86_64-linux.hello

# overlays 位置不变
overlays/foo/default.nix  →  overlays.foo
```

## 使用 mkSystem 过渡

如果有不符合约定的特殊主机，可以用 `mkSystem` 显式声明，与自动发现并存：

```nix
outputs = inputs:
  let
    snowveil = inputs.snowveil.lib.mkLib { inherit inputs; };
  in
  inputs.snowveil.lib.mkFlake {
    inherit inputs;
    outputs.extra = {
      nixosConfigurations.special-host = snowveil.mkSystem {
        host = "special-host";
        system = "x86_64-linux";
        modules = [ ./special/config.nix ];
      };
    };
  };
```

## 常见问题

**Q：`inputs.snowveil.mkFlake` 还是 `inputs.snowveil.lib.mkFlake`？**

始终使用 `inputs.snowveil.lib.mkFlake`。`lib` 是框架的 output 命名空间，`mkFlake` 在其下。

**Q：迁移后 `config` 在模块外层不能用了？**

这是旧的兼容探测模式的限制。迁移到 `meta.nix` 后，`default.nix` 只交给 NixOS module system，外层可以正常使用 `config`。

**Q：overlays 没有自动应用到 HM？**

检查 `home.useGlobalPkgs`：默认 `true` 时 HM 复用 NixOS pkgs（含 overlay）；`false` 时框架会注入 overlays 到 HM 自己的 nixpkgs。
