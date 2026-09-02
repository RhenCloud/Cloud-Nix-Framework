# Patch Helper

框架提供 `snowveil.patches` helper，用于在 overlay 中以可复现方式引用补丁。

## API

### `snowveil.patches.local`

引用本地 `.patch` 文件：

```nix
snowveil.patches.local ./fix-something.patch
```

路径透传，适合本地维护的补丁。

### `snowveil.patches.fromCommit`（推荐）

固定到特定 commit 的补丁，可复现性高：

```nix
snowveil.patches.fromCommit {
  inherit (prev) fetchpatch;
  owner = "NixOS";
  repo = "nixpkgs";
  rev = "abc123def456abc123def456abc123def456abc1";  # 完整 SHA
  hash = "sha256-...";
}
```

`rev` 固定到 commit hash，即使 PR 再次推送也不会改变。

### `snowveil.patches.fromPR`（已弃用）

```nix
# 不推荐：PR 再次推送后 hash 变化
snowveil.patches.fromPR {
  inherit (prev) fetchpatch;
  owner = "NixOS";
  repo = "nixpkgs";
  pr = 12345;
  hash = "sha256-...";
}
```

改用 `fromCommit` 固定到 PR merge commit。

## 在 overlay 中使用

```nix
# overlays/my-pkg/default.nix
extras: final: prev: {
  my-pkg = prev.my-pkg.overrideAttrs (old: {
    patches = (old.patches or [ ]) ++ [
      (extras.snowveil.patches.local ./fix.patch)
      (extras.snowveil.patches.fromCommit {
        inherit (prev) fetchpatch;
        owner = "upstream";
        repo = "my-pkg";
        rev = "deadbeef...";
        hash = "sha256-...";
      })
    ];
  });
}
```

## 注意事项

- `snowveil.patches` 只是路径/fetcher helper，补丁本身仍需用 `fetchpatch` 等标准工具下载。
- GitHub 以外的托管平台需要手动构造 URL，使用 `fetchpatch` 的 `url` 参数。
