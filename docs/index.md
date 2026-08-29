---
layout: home

hero:
  name: Cloud Nix Framework
  text: 约定优于配置的 NixOS 框架
  tagline: 零 flake-utils / flake.parts 运行时依赖，纯 nixpkgs.lib 实现
  actions:
    - theme: brand
      text: 快速开始
      link: /guide/introduction
    - theme: alt
      text: 在 GitHub 查看
      link: https://github.com/RhenCloud/Cloud-Nix-Framework

features:
  - title: 目录即配置
    details: hosts/、homes/、modules/ 自动发现，无需手动注册
  - title: NixOS + Home Manager 双对象
    details: 一次声明，同时生成 nixosConfigurations 与 homeConfigurations
  - title: 补丁与 overlay 统一
    details: cloud.patches.local / fromPR 内置，overlay 自动注入
---
