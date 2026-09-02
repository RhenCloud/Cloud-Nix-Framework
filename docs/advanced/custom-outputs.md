# 自定义 Outputs

## outputs.extra

不适合目录约定的 outputs 可通过 `outputs.extra` 添加：

```nix
outputs.extra = {
  hydraJobs = { };
  darwinConfigurations.my-mac = { };
  myCustomOutput = { };
};
```

`outputs.extra` 通过 `lib.recursiveUpdate` 与框架生成的 outputs 合并，同名 key 由 `outputs.extra` 覆盖。`outputs.expected` 不检查 `outputs.extra`，只检查框架负责发现和生成的集合。

## 非标准 outputs 警告

`deploy`、`homeModules`、`images`、`options` 等属于生态约定或框架扩展。原生 `nix flake check` 可能输出 `unknown flake output`，这不等同于 derivation 或框架检查失败，框架库也无法拦截该原生警告。

```bash
nix flake check path:. --show-trace
nix flake check path:. --all-systems --show-trace
```

## outputs.expected 期望校验

```nix
outputs.expected = {
  mode = "exact"; # 默认是 "subset"

  hosts = [ "nixos-desktop" ];
  homes = [ "rhencloud@nixos-desktop" ];

  packages.x86_64-linux = [ "hello" ];
  apps.x86_64-linux = [ "default" ];
  checks.x86_64-linux = [ "source" ];
  devShells.x86_64-linux = [ "default" ];

  overlays = [ "default" ];
  nixosModules = [ "desktop.audio" ];
  homeModules = [ "desktop.audio" ];
  formatter = [ "x86_64-linux" ];

  deploy = {
    present = true;
    nodes = [ "nixos-desktop" ];
  };

  images.nixos-desktop = [ "iso" ];
};
```

- `subset` 只报告缺失项目，兼容旧行为；`exact` 同时报告缺失和意外项目。
- `packages`、`apps`、`checks`、`devShells` 支持 `system → names`。旧的名称列表仍表示所有 systems 使用同一期望集合。
- `checks` 只比较用户 `checks/` 目录；`snowveil-*` 内部检查不参与。
- `formatter` 是应生成 formatter 的 system 列表。
- `deploy.nodes` 比较 `deploy.nodes` 的属性名。
- `images` 比较主机 metadata 声明的格式。
- exact 模式下未声明的支持类型按空集合处理。
- `meta.enable`、`meta.systems` 和 `outputs.disabled` 已生效后的最终集合才参与比较。

## 配置求值检查

Discovery 成功不代表 NixOS 或 Home Manager 配置可完整求值。可按需启用：

```nix
outputs.eval = {
  hosts = [ "nixos-desktop" ];
  homes = [ "rhencloud@nixos-desktop" ];
};
```

框架为每个 system 生成：

```text
checks.<system>.snowveil-eval-hosts
checks.<system>.snowveil-eval-homes
```

两项默认关闭，也可设为 `true` 检查全部目标。列表中的名称必须已经被发现；未知名称或错误类型会在求值 checks 时直接报错。检查分别求值 NixOS `system.build.toplevel.drvPath` 和 Home Manager `activationPackage.drvPath`，并移除字符串 context，避免轻量检查持有目标 derivation 的 GC 引用。

## 诊断输出控制

默认生成 discovery JSON、全局 DOT 和 per-host DOT。只需要轻量 CI 时可关闭部分诊断：

```nix
outputs.diagnostics = {
  discovery = false;
  moduleGraph = true;
  perHostModuleGraph = false;
};
```

- `discovery = false`：不生成 `snowveil-discovery`。
- `moduleGraph = false`：不生成 `snowveil-module-graph-dot`。
- `perHostModuleGraph = false`：保留全局模块图，但省略 discovery 的 `perHost` 内容和 DOT 的 `hosts/` 子目录。

## 使用 mkSystem / mkHome 手动构造

```nix
outputs.extra.nixosConfigurations.special = snowveil.mkSystem {
  host = "special";
  system = "x86_64-linux";
  modules = [ ./special.nix ];
};
```
