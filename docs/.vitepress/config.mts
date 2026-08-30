import { defineConfig } from 'vitepress'

export default defineConfig({
  lang: 'zh-CN',
  title: 'Cloud Nix Framework',
  description: '基于 Nix Flakes 的配置框架',
  cleanUrls: true,
  lastUpdated: '最后更新于',
  themeConfig: {
    outline: { level: [2, 3], label: '本页目录' },
    nav: [
      { text: '首页', link: '/' },
      { text: '指南', link: '/guide/introduction' },
      { text: '核心 API', link: '/api/core' },
      { text: '参考', link: '/reference/discovery' }
    ],
    sidebar: {
      '/guide/': [
        {
          text: '指南',
          items: [
            { text: '介绍', link: '/guide/introduction' },
            { text: '快速开始', link: '/guide/getting-started' },
            { text: '目录结构', link: '/guide/directory-structure' },
            { text: '模块写作', link: '/guide/modules' },
            { text: 'Overlays 与补丁', link: '/guide/overlays-patches' },
            { text: '扩展 outputs', link: '/guide/extensions' },
            { text: '密钥管理', link: '/guide/sops' }
          ]
        }
      ],
      '/api/': [
        {
          text: '核心 API',
          items: [{ text: '核心 API', link: '/api/core' }]
        }
      ],
      '/reference/': [
        {
          text: '参考',
          items: [{ text: 'Discovery 规范', link: '/reference/discovery' }]
        }
      ]
    },
    socialLinks: [
      { icon: 'github', link: 'https://github.com/RhenCloud/Cloud-Nix-Framework' }
    ],
    editLink: {
      pattern: 'https://github.com/RhenCloud/Cloud-Nix-Framework/edit/main/docs/:path',
      text: '编辑此页'
    },
    search: { provider: 'local' },
    sidebarMenuLabel: '菜单',
    returnToTopLabel: '返回顶部',
    docFooter: { prev: '上一页', next: '下一页' },
    footer: {
      message: 'MIT 许可发布',
      copyright: 'Copyright © 2026 RhenCloud'
    }
  }
})
