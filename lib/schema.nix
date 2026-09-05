# Snowveil 框架契约定义
# ================================
# 本文件定义了 Snowveil flake 和生成的用户 flake 的输出 schema
# 用于 Nix 工具的 flake output 类型检查和发现、减少"unknown flake output"噪音
#
# 标准化输出发现：
# - 元 flake (snowveil 框架本身) 声明自己的 outputs
# - mkFlake 生成的用户 flake 在其 outputs 中包含 flakeOutputsSchema
# - 工具可以查询 flakeOutputsSchema 了解 flake 的合法输出
#
# 参考：
# - https://nixos.org/manual/nix/stable/command-ref/new-cli/nix3-flake.html
# - Nix RFC 87: Trusted users in flakes (schema discussion)

{ lib }:

{
  # 元 flake (snowveil 框架本身) 的已知 outputs
  metaFlakeOutputs = {
    # 编程接口
    lib = "attribute set - Snowveil 库、类型、工具集合";
    
    # 用户相关
    templates = "attribute set - flake 模板（default）";
    
    # 质量保证
    checks = "per-system derivations - 框架自身的测试和验证";
    devShells = "per-system attribute - 开发环境（default）";
    formatter = "per-system derivation - 代码格式化工具";
    
    # 文档
    options = "per-system text file - NixOS 选项文档 (JSON)";
    flakeOutputsSchema = "attribute set - 本 schema 文档";
  };

  # 用户 flake (通过 mkFlake 生成) 的标准 outputs
  # 这些会由框架自动生成，但具体项目可能选择性启用/禁用某些输出
  # 参见 mkFlake 的 outputs.disabled 参数
  userFlakeOutputs = {
    # 主机与用户配置（核心）
    nixosConfigurations = "attribute set - NixOS 主机配置（key = hostname）";
    homeConfigurations = "attribute set - Home Manager 用户配置（key = user@host or user）";
    
    # 包和应用
    packages = "per-system derivations - 可构建的包";
    apps = "per-system app specifications - 应用程序包装器";
    
    # 模块和能力扩展
    nixosModules = "attribute set - 可复用的 NixOS 模块（key = grouped.path）";
    homeModules = "attribute set - 可复用的 Home Manager 模块（key = grouped.path）";
    
    # 依赖包管理
    overlays = "attribute set - nixpkgs overlays（key = name）";
    
    # 开发与测试
    devShells = "per-system attribute - 开发环境（key = name）";
    checks = "per-system derivations - 测试和验证检查";
    
    # 输出构件
    images = "attribute set - 系统镜像（NixOS ISO, VM 镜像等）";
    deploy = "attribute set - deploy 配置（用于自动部署）";
    formatter = "per-system derivation - 代码格式化工具";
    
    # 库与扩展
    lib = "attribute set - 项目特定的库函数和工具";
  };

  # 对标准化的完整参考
  documentationNote = ''
    Snowveil 框架通过显式声明 flakeOutputsSchema 来标记所有已知的 outputs
    这减少了 Nix 工具（如 nix flake show）的 "unknown flake output" 警告
    
    该 schema 既供人类阅读，也可被工具解析以增强自动化能力
  '';

  # 所有已知的 output 类型（不含系统维度）
  allKnownOutputTypes = [
    # 元 flake
    "lib"
    "templates"
    "checks"
    "devShells"
    "formatter"
    "options"
    "flakeOutputsSchema"
    # 用户 flake
    "nixosConfigurations"
    "homeConfigurations"
    "packages"
    "apps"
    "nixosModules"
    "homeModules"
    "overlays"
    "images"
    "deploy"
  ];
}
