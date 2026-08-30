---
layout: home

hero:
  name: Cloud Nix Framework
  text: 约定优于配置的 NixOS 框架
  tagline: 目录结构即配置意图，自动发现主机、模块与 Home Manager 配置
  actions:
    - theme: brand
      text: 快速开始
      link: /guide/getting-started
    - theme: alt
      text: 设计理念
      link: /concepts/philosophy
    - theme: alt
      text: 在 GitHub 查看
      link: https://github.com/RhenCloud/Cloud-Nix-Framework

features:
  - title: 目录即配置
    details: hosts/、homes/、modules/ 自动发现，无需手动注册 import 或 nixosConfigurations
  - title: NixOS + Home Manager 双对象
    details: 单树模块、单次声明，同时生成 nixosConfigurations 与 homeConfigurations
  - title: 角色系统
    details: 通过 roles 声明，自动决定哪些模块注入哪台主机，desktop/server/development 按需组合
  - title: 零运行时依赖
    details: 纯 nixpkgs.lib 实现，无 flake-utils / flake.parts 依赖
  - title: 统一 nixpkgs 配置
    details: allowUnfree、overlay 统一作用于 NixOS、HM 与所有 per-system outputs
  - title: 惰性求值
    details: 发现阶段纯文件扫描，nix flake show 不触发主机 config 求值
---
