# Overlays 与补丁

`overlays/<name>/default.nix` 会生成 `overlays.<name>`。所有自动发现的 overlays 还会统一应用到：

- NixOS 的 `pkgs`；
- 独立与嵌入式 home-manager 的 `pkgs`；
- packages、devShells、checks、apps 与 formatter。

因此 `packages/<name>/default.nix` 可以直接通过函数参数使用 overlay 新增的包。

```nix
# overlays/foo/default.nix
{ cloud }: final: prev: {
  foo = prev.foo.overrideAttrs (old: {
    patches = (old.patches or [ ]) ++ [
      (cloud.patches.local ./fix.patch)
      (cloud.patches.fromPR {
        inherit (prev) fetchpatch;
        owner = "NixOS";
        repo = "nixpkgs";
        pr = 123456;
        hash = "sha256-...";
      })
    ];
  });
}
```

## 统一 nixpkgs 配置

```nix
outputs = inputs:
  inputs.cloud.lib.mkFlake {
    inherit inputs;

    nixpkgsConfig = {
      allowUnfree = true;
      permittedInsecurePackages = [ "example-1.0" ];
    };

    extraOverlays = [
      (final: prev: {
        # 在自动发现 overlays 之后应用
      })
    ];
  };
```

框架不再让自动发现的 package 单独使用未经配置的 `nixpkgs.legacyPackages`，从而避免 NixOS、home-manager 与其他 outputs 的包集合不一致。

## patch helper

- `cloud.patches.local path`：本地 `.patch` 文件，路径透传。
- `cloud.patches.fromPR { fetchpatch; owner; repo; pr; hash; }`：构造 GitHub PR patch URL 并通过 `fetchpatch` 拉取。`hash` 应固定以保证可复现。

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
