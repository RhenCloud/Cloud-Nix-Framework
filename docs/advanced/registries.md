# 外部模块注册表（moduleRegistries）

`moduleRegistries` 允许将外部 flake 的模块注入到自动发现的模块列表中，与本地 `modules/` 下的模块一同按角色过滤和字典序排列。

## 用法

```nix
outputs = inputs:
  inputs.cloud.lib.mkFlake {
    inherit inputs;

    moduleRegistries = [
      {
        # 外部 NixOS 模块列表
        nixos = [ inputs.some-flake.nixosModules.default ];
        # 外部 HM 模块列表
        home = [ inputs.some-flake.homeManagerModules.default ];
        # 角色过滤（null 表示始终注入）
        roles = [ "desktop" ];
      }
    ];
  };
```

## 与 extraNixosModules 的区别

| | `moduleRegistries` | `extraNixosModules` |
| ---- | ---- | ---- |
| 角色过滤 | 支持 | 不支持（始终注入） |
| 注入时机 | 与 modules/ 同序 | 最后注入 |
| 用途 | 外部模块按角色集成 | 无条件附加模块 |

## 典型场景

将 nixos-hardware 的硬件模块按角色注入：

```nix
moduleRegistries = [
  {
    nixos = [ inputs.nixos-hardware.nixosModules.lenovo-thinkpad-x1 ];
    roles = [ "laptop" ];
  }
];
```
