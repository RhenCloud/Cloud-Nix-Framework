# Overlays 与补丁

`overlays/<name>/default.nix` 会生成 `overlays.<name>`。所有自动发现的 overlays 还会统一应用到：

- NixOS 的 `pkgs`；
- 独立与嵌入式 home-manager 的 `pkgs`；
- packages、devShells、checks、apps 与 formatter。

因此 `packages/<name>/default.nix` 可以直接通过函数参数使用 overlay 新增的包。

## Overlay 文件签名

框架支持两种 overlay 文件签名：

**标准 nixpkgs overlay**（直接返回 `final: prev:` 函数）：

```nix
# overlays/foo/default.nix
final: prev: {
  foo = prev.foo.override { bar = true; };
}
```

**带框架参数的扩展签名**（第一个参数接收 `{ inputs, self, cloud }`）：

```nix
# overlays/foo/default.nix
extras: final: prev: {
  foo = prev.foo.overrideAttrs (old: {
    patches = (old.patches or [ ]) ++ [
      (extras.cloud.patches.local ./fix.patch)
      (extras.cloud.patches.fromCommit {
        inherit (prev) fetchpatch;
        owner = "NixOS";
        repo = "nixpkgs";
        rev = "abc123def456";
        hash = "sha256-...";
      })
    ];
  });
}
```

也可使用解构参数：

```nix
{ cloud, inputs, self }: final: prev: {
  ...
}
```

框架通过 `functionArgs` 检测解构签名（参数名含 `inputs`、`self` 或 `cloud`）；若检测不到，则尝试以 `{ inherit inputs self cloud; }` 调用，如返回函数则视为扩展签名，否则当作普通 overlay 使用。

## 统一 nixpkgs 配置

```nix
outputs = inputs:
  inputs.cloud.lib.mkFlake {
    inherit inputs;

    nixpkgs = {
      config = {
        allowUnfree = true;
        permittedInsecurePackages = [ "example-1.0" ];
      };
      overlays = [
        (final: prev: {
          # 在自动发现 overlays 之后应用
        })
      ];
    };
  };
```

框架不再让自动发现的 package 单独使用未经配置的 `nixpkgs.legacyPackages`，从而避免 NixOS、home-manager 与其他 outputs 的包集合不一致。

嵌入式 HM 默认使用 `home-manager.useGlobalPkgs = true`。若 Stylix 等 HM 模块需要设置自己的 overlay，可全局或按主机设置 `home.useGlobalPkgs = false`。框架会把基础 `nixpkgs.config` 与 overlays 注入 HM 自己的 nixpkgs，避免丢失统一配置：

```nix
# hosts/nixos-desktop/meta.nix
{
  home.useGlobalPkgs = false;
}
```

::: warning Stylix 兼容说明

Stylix 的某些模块（`nixos-icons`、`gtksourceview`）会在 HM 侧设置 overlay。启用 `useGlobalPkgs = true` 时会触发 Home Manager 警告：

> You have set either nixpkgs.config or nixpkgs.overlays while using home-manager.useGlobalPkgs. This will soon not be possible.

此警告来自 Stylix 本身，不是框架重复配置。如需消除警告，请对包含 Stylix 的主机设置 `home.useGlobalPkgs = false`。

:::

## Patch helper

- `cloud.patches.local path`：本地 `.patch` 文件，路径透传。
- `cloud.patches.fromCommit { fetchpatch; owner; repo; rev; hash; }`：固定到具体 commit，可复现性高。推荐用法。
- `cloud.patches.fromPR { fetchpatch; owner; repo; pr; hash; }`：**已弃用**，PR 再次推送后 hash 变化；请改用 `fromCommit`。

```nix
# 推荐：固定到 commit hash
cloud.patches.fromCommit {
  inherit (prev) fetchpatch;
  owner = "NixOS";
  repo = "nixpkgs";
  rev = "abc123def456abc123def456abc123def456abc1";
  hash = "sha256-...";
}
```

## 多版本包

多版本包需求仍可按需集成 nixpkgs-multiverse：

```nix
{ inputs, ... }:
{
  imports = [ inputs.multiverse.nixosModules.default ];
  multiverse.enable = true;
  multiverse.pins.python3 = "3.8.9";
}
```
