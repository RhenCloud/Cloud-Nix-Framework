# 自定义 Outputs

## extraOutputs

不适合目录约定的 outputs 可通过 `extraOutputs` 添加：

```nix
outputs = inputs:
  inputs.cloud.lib.mkFlake {
    inherit inputs;

    extraOutputs = {
      # 标准 flake outputs
      hydraJobs = { };
      darwinConfigurations.my-mac = { };

      # 非标准 outputs（nix flake check 可能警告但不报错）
      myCustomOutput = { };
    };
  };
```

`extraOutputs` 通过 `lib.recursiveUpdate` 与框架生成的 outputs 合并，同名 key 由 `extraOutputs` 覆盖。

## 非标准 outputs 警告

`deploy`、`homeModules`、`images`、`options` 等属于生态约定或框架自定义 output。`nix flake check` 可能输出 `unknown flake output` 警告，不表示 derivation 失败。

推荐检查命令：

```bash
nix flake check path:. --show-trace
nix flake check path:. --all-systems --show-trace  # 检查全部架构
```

## expectedOutputs 期望校验

在 `mkFlake` 中声明期望的 output 列表，框架会在 `cloud-discovery` check 中验证：

```nix
inputs.cloud.lib.mkFlake {
  inherit inputs;

  expectedOutputs = {
    hosts = [ "nixos-desktop" "nixos-server" "yc-hk-1" ];
    homes = [ "rhencloud@nixos-desktop" ];
    packages = [ "hello" ];
  };
};
```

`cloud-discovery` 失败时给出明确报错，帮助在重构时尽早发现意外丢失的配置。

## 使用 mkSystem / mkHome 手动构造

对于不符合目录约定的特殊主机：

```nix
extraOutputs = {
  nixosConfigurations.special = cloud.mkSystem {
    host = "special";
    system = "x86_64-linux";
    modules = [ ./special.nix ];
    extraSpecialArgs = { myArg = true; };
  };
};
```
