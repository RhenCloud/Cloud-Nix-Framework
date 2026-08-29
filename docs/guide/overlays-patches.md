# Overlays 与补丁

框架在 `cloud` 命名空间提供 `patches` helper，简化对 nixpkgs / flake inputs 包打补丁的样板。patch 逻辑写在 `overlays/<name>/default.nix`（就近原则，本地 patch 与 overlay 同目录）。

```nix
# overlays/foo/default.nix
{ cloud }: final: prev: {
  foo = prev.foo.overrideAttrs (oa: {
    patches = (oa.patches or []) ++ [
      (cloud.patches.local ./fix.patch)          # 本地 patch
      (cloud.patches.fromPR {                    # GitHub PR patch
        inherit (prev) fetchpatch;
        owner = "NixOS";
        repo = "nixpkgs";
        pr = 123456;
        hash = "sha256-...";                     # 留 null 让 nix 报出期望 hash 后回填
      })
    ];
  });
}
```

## patch helper

- `cloud.patches.local path`：本地 `.patch` 文件，路径透传。
- `cloud.patches.fromPR { fetchpatch; owner; repo; pr; hash; }`：拼接 `https://github.com/<owner>/<repo>/pull/<pr>.patch` 并用 `fetchpatch` 拉取。`hash` 必须固定以保证可复现，开发期可置 `null` 触发报错回填。

## 多版本包

多版本包需求（如锁定某个包的旧版本）不通过多 nixpkgs channel 实现，而是可选集成 [nixpkgs-multiverse](https://github.com/fzakaria/nixpkgs-multiverse)：

```nix
{ inputs, ... }: {
  imports = [ inputs.multiverse.nixosModules.default ];
  multiverse.enable = true;
  multiverse.pins.python3 = "3.8.9";
}
```