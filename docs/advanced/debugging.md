# 调试与问题排查

## cloud-discovery 报告

查看框架发现了哪些主机、模块和包：

```bash
nix build .#checks.x86_64-linux.cloud-discovery
cat result | python3 -m json.tool
```

输出字段：

- `hosts`：发现的主机列表
- `homes`：发现的 home 列表（含 `user@host` 格式）
- `packages`：各架构的包列表
- `modules.nixosModules`：发现的 NixOS 模块组
- `modules.homeModules`：发现的 HM 模块组

## 常见问题

### 主机未被发现

原因：

1. 目录后缀不合法（不在 `lib.systems.flakeExposed` 中）
2. 缺少 `default.nix`
3. 在 `disabledOutputs` 中
4. `meta.nix` 的 `enable = false`

检查：

```bash
# 查看 flake check 输出
nix flake check path:. --show-trace 2>&1 | grep -i "skip\|trace\|warn"
```

### 模块被意外注入或未注入

原因：角色配置不正确，或 `_common` 前缀使用错误。

检查 `cloud-discovery` 报告中 `modules` 字段的角色归属。

### 嵌入式 HM 报"option not found"

模块在 `_common/nixos.nix` 中引用了 `home-manager.*` 选项，但该主机关闭了 HM 嵌入。

解决：

1. 使用 `cloud.homeManager.backupFileExtension` 代替 `home-manager.backupFileExtension`
2. 或将该配置移到按角色过滤的模块

### VitePress 构建错误：`Element is missing end tag`

原因：Markdown 中有未转义的 `<` 或 `>`，VitePress 将其解析为 HTML 标签。

修复：将 `<name>` 等占位符改为代码块中使用，或在行内使用 `&lt;name&gt;`。

### `nix flake check` 报 `unknown flake output`

这是 Nix 对非标准 output（如 `deploy`、`options`、`homeModules`）的警告，不影响构建。预期行为。

## trace 调试

框架在发现阶段跳过或降级处理时会输出 `builtins.trace` 信息：

```bash
nix flake check path:. --show-trace 2>&1 | grep "trace:"
```

常见 trace：

- `trace: [CNF] 主机 foo 缺少 default.nix，跳过` → 缺少主机文件
- `trace: [CNF] meta.nix 字段 embedHomeManager 已弃用` → 使用了旧字段
- `trace: [CNF] 发现 homes/... 但找不到对应主机` → host.nix 文件名与主机目录不匹配

## 隔离求值

仅求值一台主机，避免所有主机同时触发：

```bash
nix eval .#nixosConfigurations.nixos-desktop.config.system.stateVersion
nix build .#nixosConfigurations.nixos-desktop.config.system.build.toplevel
```
