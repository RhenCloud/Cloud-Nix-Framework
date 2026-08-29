# 密钥管理（sops）

框架内置 sops-nix 集成的 helper，不硬编码 input，走「约定 + 助手」：

- 自动按 `secrets/common.yaml` 与 `secrets/hosts/<host>.yaml` 组合各机的 `defaultSopsFile`。
- 自动注入 sops-nix 模块。
- sops-nix input 由用户通过 `follows` 提供，框架不强制固定。

```nix
{ inputs, ... }: {
  # sops-nix 由用户引入，框架的 cloud.sops 负责组合文件与注入模块
}
```

约定路径：

```
secrets/
├── common.yaml          # 所有主机共享的密钥
└── hosts/
    └── <host>.yaml      # 单主机专属密钥
```