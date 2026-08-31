# 扩展 outputs

框架原生支持 apps、formatter 与 deploy 目录约定。目录不存在或被禁用时不会生成对应 output。

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

formatter 与 packages、checks 等使用同一套 `nixpkgs.config` 和 overlays。

## Deploy

`deploy/default.nix` 直接映射为顶层 `deploy`，可返回 deploy-rs 所需配置：

```nix
# deploy/default.nix
{ self, ... }:
{
  nodes = { };
}
```

部署工具本身仍由用户通过 flake input 引入，框架只负责输出约定与自动发现。

## 禁用自动发现的 output

`outputs.disabled` 在调用 output 文件前过滤条目，适合临时关闭损坏或昂贵的 check：

```nix
inputs.cloud.lib.mkFlake {
  inherit inputs;

  outputs.disabled = [
    "checks.eval-nixos-desktop"
    "checks.aarch64-linux.only-broken-there"
    "packages.some-package"
    "apps.debug"
    "formatter"
    "deploy"
  ];
}
```

无 system 的标识会在所有架构禁用；`<kind>.<system>.<name>` 只禁用一个架构。支持的 kind 包括 `packages`、`checks`、`apps`、`devShells`、`formatter` 与 `deploy`。

也可使用分类属性集：

```nix
outputs.disabled = {
  checks = [ "eval-nixos-desktop" ];
  packages = [ "some-package" ];
};
```

`outputs.disabled` 只控制框架自动发现的条目；`outputs.extra` 仍可显式添加同名 output。

## Output 元数据

packages、checks、apps 与 shells 可在同目录添加 `meta.nix`：

```nix
# checks/expensive/meta.nix
{
  enable = false;
  systems = [ "x86_64-linux" ];
}
```

`meta.nix` 必须直接返回属性集。目前支持：

- `enable`：布尔值，设为 `false` 时不会调用 `default.nix`；
- `systems`：允许生成该 output 的系统列表。

formatter 与 deploy 也可使用同目录的 `meta.nix`；deploy 只使用 `enable`。

## Package 的单架构约定

推荐使用无歧义的 system-first 目录：

```text
packages/x86_64-linux/foo/default.nix
```

它生成 `packages.x86_64-linux.foo`。旧的：

```text
packages/foo.x86_64-linux/default.nix
```

继续兼容。若包名本身以 system 结尾，可通过元数据保留完整包名：

```text
packages/foo.x86_64-linux/
├── default.nix
└── meta.nix
```

```nix
{
  systems = [ "x86_64-linux" ];
}
```

此时 output 名是 `packages.x86_64-linux."foo.x86_64-linux"`。

## `nix flake check` 与非标准 outputs

`deploy`、`homeModules`、`images`、`options` 等属于生态约定或框架自定义 output。不同 Nix 版本运行 `nix flake check` 时可能输出 `unknown flake output` 警告；这类警告本身不表示 derivation 失败。

推荐检查命令：

```bash
nix flake check path:. --show-trace
```

需要检查全部配置架构时使用：

```bash
nix flake check path:. --all-systems --show-trace
```

框架会生成标准的 `checks.<system>.cloud-discovery`，记录发现到的 hosts、homes、packages 与模块 output。`checks/` 下的 `cloud-` 前缀由框架保留。

## 其他 outputs

不适合目录约定的 outputs 可使用 `outputs.extra`：

```nix
inputs.cloud.lib.mkFlake {
  inherit inputs;
  outputs.extra = {
    hydraJobs = { };
  };
}
```
