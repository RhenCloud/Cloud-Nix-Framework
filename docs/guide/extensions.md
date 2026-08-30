# 扩展 outputs

框架原生支持 apps、formatter 与 deploy 目录约定。目录不存在时不会生成对应 output。

## Apps

`apps/<name>/default.nix` 映射为 `apps.<system>.<name>`。文件通过统一包集合的 `pkgs.callPackage` 调用，应返回标准 app attrset：

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

除普通包参数外，函数还可按需声明 `inputs`、`self`、`cloud`。

## Formatter

`formatter/default.nix` 映射为每个目标架构的 `formatter.<system>`：

```nix
# formatter/default.nix
{ nixfmt }:
nixfmt
```

之后可运行：

```bash
nix fmt
```

formatter 与 packages、checks 等使用同一套 `nixpkgsConfig` 和 overlays。

## Deploy

`deploy/default.nix` 直接映射为顶层 `deploy`，可返回 deploy-rs 所需配置：

```nix
# deploy/default.nix
{ self, ... }:
{
  nodes = { };
}
```

该文件可按需声明 `lib`、`inputs`、`self`、`cloud`。部署工具本身仍由用户通过 flake input 引入，框架只负责输出约定与自动发现。

## 其他 outputs

不适合目录约定的 outputs 可继续使用 `extraOutputs`：

```nix
inputs.cloud.lib.mkFlake {
  inherit inputs;
  extraOutputs = {
    hydraJobs = { };
  };
}
```
