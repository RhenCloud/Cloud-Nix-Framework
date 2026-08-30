# Packages 与 Apps

## 目录约定

框架支持三种 package 布局：

| 布局 | 示例 | 说明 |
| ---- | ---- | ---- |
| 跨平台（推荐） | `packages/hello/default.nix` | 对所有 `systems` 生成 |
| system-first（推荐） | `packages/x86_64-linux/hello/default.nix` | 仅对应架构 |
| 后缀兼容（不推荐） | `packages/hello.x86_64-linux/default.nix` | 旧式，可能歧义 |

新配置推荐使用**跨平台**或 **system-first** 两种，避免点号歧义。

## 包文件签名

```nix
# packages/hello/default.nix
{ stdenv, lib, ... }:
stdenv.mkDerivation {
  pname = "hello";
  version = "1.0";
  src = ./.;
}
```

除标准 pkgs 参数外，可按需声明 `inputs`、`self`、`cloud`：

```nix
{ stdenv, inputs, ... }:
stdenv.mkDerivation {
  src = inputs.my-source;
}
```

## nixpkgsConfig 统一配置

自动发现的包使用与 NixOS/HM 相同的 `nixpkgs` 实例（含 `nixpkgsConfig` 与 overlays），不再使用未经配置的 `legacyPackages`：

```nix
outputs = inputs:
  inputs.cloud.lib.mkFlake {
    inherit inputs;
    nixpkgsConfig = {
      allowUnfree = true;
    };
    extraOverlays = [ (final: prev: { myPkg = ...; }) ];
  };
```

## Apps

`apps/<name>/default.nix` 映射为 `apps.<system>.<name>`：

```nix
# apps/hello/default.nix
{ lib, hello }:
{
  type = "app";
  program = lib.getExe hello;
}
```

```bash
nix run .#hello
```

## Formatter

```nix
# formatter/default.nix
{ nixfmt }:
nixfmt
```

```bash
nix fmt
```

## 禁用特定 output

```nix
inputs.cloud.lib.mkFlake {
  inherit inputs;
  disabledOutputs = [
    "packages.some-broken-package"
    "checks.x86_64-linux.expensive"
    "apps.debug"
  ];
}
```

也可用 `meta.nix` 禁用单个条目：

```nix
# packages/some-package/meta.nix
{
  enable = false;
  systems = [ "x86_64-linux" ];  # 限制架构
}
```
