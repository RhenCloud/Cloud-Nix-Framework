import { defineConfig } from 'vitepress'

export default defineConfig({
  lang: 'zh-CN',
  title: 'Snowveil',
  description: '基于 Nix Flakes 的配置框架',
  cleanUrls: true,
  lastUpdated: '最后更新于',
  themeConfig: {
    outline: { level: [2, 3], label: '本页目录' },
    nav: [
      { text: '首页', link: '/' },
      { text: '指南', link: '/guide/introduction' },
      { text: '概念', link: '/concepts/philosophy' },
      { text: '参考', link: '/reference/discovery' },
      { text: '迁移', link: '/migration/from-plain-flake' },
      { text: '进阶', link: '/advanced/debugging' },
    ],
    sidebar: {
      '/guide/': [
        {
          text: '入门',
          items: [
            { text: '介绍', link: '/guide/introduction' },
            { text: '快速开始', link: '/guide/getting-started' },
            { text: '目录结构', link: '/guide/directory-structure' },
          ],
        },
        {
          text: '核心功能',
          items: [
            { text: '多主机管理', link: '/guide/multiple-hosts' },
            { text: 'Home Manager', link: '/guide/home-manager' },
            { text: '角色系统', link: '/guide/roles' },
            { text: '模块写作', link: '/guide/modules' },
            { text: '模块依赖', link: '/guide/module-dependencies' },
            { text: 'Packages 与 Apps', link: '/guide/packages' },
            { text: 'Overlays 与补丁', link: '/guide/overlays-patches' },
            { text: '扩展 outputs', link: '/guide/extensions' },
            { text: '密钥管理', link: '/guide/sops' },
          ],
        },
      ],
      '/concepts/': [
        {
          text: '概念',
          items: [
            { text: '设计理念', link: '/concepts/philosophy' },
            { text: '发现机制', link: '/concepts/discovery' },
            { text: '元数据系统', link: '/concepts/metadata' },
            { text: '框架架构', link: '/concepts/architecture' },
          ],
        },
      ],
      '/reference/': [
        {
          text: '参考',
          items: [
            { text: 'Discovery 规范', link: '/reference/discovery' },
            { text: '版本策略', link: '/reference/versioning' },
            { text: '核心 API', link: '/api/core' },
          ],
        },
      ],
      '/api/': [
        {
          text: '参考',
          items: [
            { text: '核心 API', link: '/api/core' },
            { text: 'Discovery 规范', link: '/reference/discovery' },
            { text: '版本策略', link: '/reference/versioning' },
          ],
        },
      ],
      '/migration/': [
        {
          text: '迁移指南',
          items: [
            { text: '从普通 flake 迁移', link: '/migration/from-plain-flake' },
            { text: '从 snowfallorg/lib 迁移', link: '/migration/from-snowfall' },
            { text: '从 flake.parts 迁移', link: '/migration/from-flake-parts' },
          ],
        },
      ],
      '/advanced/': [
        {
          text: '进阶',
          items: [
            { text: '外部模块注册表', link: '/advanced/registries' },
            { text: '自定义 outputs', link: '/advanced/custom-outputs' },
            { text: 'Patch helper', link: '/advanced/patches' },
            { text: '调试与排查', link: '/advanced/debugging' },
          ],
        },
      ],
    },
    socialLinks: [
      { icon: 'github', link: 'https://github.com/SnowveilOrg/Snowveil' },
    ],
    editLink: {
      pattern: 'https://github.com/SnowveilOrg/Snowveil/edit/main/docs/:path',
      text: '编辑此页',
    },
    search: { provider: 'local' },
    sidebarMenuLabel: '菜单',
    returnToTopLabel: '返回顶部',
    docFooter: { prev: '上一页', next: '下一页' },
    footer: {
      message: 'MIT 许可发布',
      copyright: 'Copyright © 2026 RhenCloud',
    },
  },
})
