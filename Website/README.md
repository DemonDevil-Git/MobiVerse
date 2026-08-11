# MobiVerse 产品官网

这是一个无需构建工具的静态站点，直接使用浏览器即可预览。站点同时提供面向搜索引擎和 AI 搜索工具的结构化产品信息。

```bash
python3 -m http.server 4173 --directory Website
```

然后访问 `http://127.0.0.1:4173`。

## 文件

- `index.html`：页面结构与产品文案
- `styles.css`：视觉系统、响应式布局与轻量动效
- `script.js`：中英文切换与语言记忆、移动导航、页头状态与滚动出现效果
- `download/`：稳定下载页，通过 GitHub API 解析最新官方 Release
- `guides/`：面向具体转换问题的独立可索引指南
- `robots.txt`、`sitemap.xml`、`llms.txt`：搜索与 AI 发现入口
- `content.css`、`release.js`：内容页样式与最新版本解析
- `assets/`：生成式首屏底图、产品素材、演示视频与视频海报

## 发布维护

- 新版本发布后，下载页会自动读取 GitHub 最新 Release。
- 首页演示区使用 `assets/mobiverse-demo.mp4`（H.264）和 `assets/mobiverse-demo-poster.jpg`，网页兼容版视频同时保存到 GitHub Release。
- `download/index.html` 中保留当前已验证版本作为 GitHub API 不可用时的回退。
- 新增或删除指南时同步更新 `sitemap.xml` 和 `llms.txt`。

当前官网展示的 macOS 正式版本为 MobiVerse 2.4.1（2026-08-11）。首页的“最新版本”、下载页回退信息、结构化数据与 `llms.txt` 应在后续发布时一并更新。
