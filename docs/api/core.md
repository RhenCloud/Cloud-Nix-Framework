# 核心 API

框架通过 `lib` 输出暴露统一的命名空间 `cloud`。

## `mkFlake`

顶层 outputs 构造器，自动扫描目录并拼接出全部 outputs：

```nix
inputs.cloud.mkFlake {
  inherit inputs;                                  # 透传所有 flake inputs
  systems = [ "x86_64-linux" "aarch64-linux" ];    # 仅用于 per-system outputs（packages/checks/devShells）
  extraOutputs = { };                              # 深合并覆盖自动生成项
  extraSpecialArgs = { };                          # 追加注入模块的 specialArgs
}
```

## `mkSystem`

创建单个 `nixosConfigurations.<host>`：

```nix
cloud.mkSystem {
  host = "nixos-desktop";
  system = "x86_64-linux";     # 可为 null，从 hosts/<host>.<system>/ 派生
  modules = [ ];               # 追加到自动发现之后
  extraSpecialArgs = { };
}
```

## `mkHome`

创建单个 `homeConfigurations.<user>`：

```nix
cloud.mkHome {
  user = "rhencloud";
  host = "nixos-desktop";      # null = 全局 home；非 null = "<user>@<host>" 并继承该 host 的 system
  system = "x86_64-linux";     # 仅全局 home 必填（per-host 继承 host）
  modules = [ ];
  extraSpecialArgs = { };
}
```

## `mkLib` / `importModules` / `flattenTree`

- `mkLib { inherit inputs; }` 返回 `cloud` 命名空间。
- `importModules` / `flattenTree` 是目录自动发现工具函数，按全局路径字典序稳定遍历。

## 分层入口

`mkFlake` 覆盖常规场景，`mkSystem` / `mkHome` 作为细粒度逃生舱，兼顾零样板与例外处理。