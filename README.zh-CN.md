# MobiVerse

**MobiVerse 是一款本地优先的 macOS 与 Windows 阅读转换工具：可以直接打开 EPUB，也可以把 Kindle 电子书、漫画压缩包和 PDF 漫画转换成适合 Apple Books 与现代 EPUB 阅读器使用的精致 EPUB。**

> English: [README.md](README.md)

<p align="center">
  <img src="Docs/hero.svg" alt="MobiVerse converts illustrated books into Apple Books-friendly EPUBs" width="100%">
</p>

<p align="center">
  <a href="https://github.com/DemonDevil-Git/MobiVerse/releases/latest/download/MobiVerse-2.4.1.dmg"><img src="https://img.shields.io/badge/macOS%202.4.1-%E4%B8%8B%E8%BD%BD-1764D8?style=for-the-badge&logo=apple&logoColor=white" alt="下载 MobiVerse 2.4.1 macOS 版"></a>
  <a href="https://github.com/DemonDevil-Git/MobiVerse/releases/download/v2.2.0/MobiVerse-2.2.0-Windows11-ARM64-Setup.exe"><img src="https://img.shields.io/badge/Windows%202.2.0-%E4%B8%8B%E8%BD%BD-1764D8?style=for-the-badge&logo=windows11&logoColor=white" alt="下载 MobiVerse 2.2.0 Windows 版"></a>
  <a href="https://github.com/DemonDevil-Git/MobiVerse/releases"><img src="https://img.shields.io/github/v/release/DemonDevil-Git/MobiVerse?style=for-the-badge&label=%E6%9C%80%E6%96%B0%E7%89%88%E6%9C%AC" alt="最新版本"></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/License-GPLv3-111827?style=for-the-badge" alt="GPLv3 license"></a>
</p>

<p align="center">
  <strong>普通用户无需单独安装 Calibre。</strong> 适合漫画、图像型 Kindle 书籍、漫画压缩包，以及需要在 Apple Books 中稳定阅读的 EPUB 输出。
</p>

## 产品演示

https://github.com/user-attachments/assets/485accd5-569d-45ed-b25f-5643ba96d3fc

观看[官网演示](https://mobiverse-coral.vercel.app/#demo)，或从 GitHub Releases 下载官方 [H.264 MP4](https://github.com/DemonDevil-Git/MobiVerse/releases/download/v2.4.1/MobiVerse-2.4.1-Demo.mp4) 与[原始 HEVC MOV](https://github.com/DemonDevil-Git/MobiVerse/releases/download/v2.4.1/MobiVerse-2.4.1-Demo-Original.mov)。

## MobiVerse 2.4.1 更新说明

MobiVerse 2.4.1 (14) 发布于 2026 年 8 月 11 日，重点提升 macOS 首次启动可靠性与工作区布局：

- **修复新安装后的首次启动闪退**：本地化资源会从安装包中的真实位置安全加载，新用户第一次打开不再因开发环境资源路径失效而退出。
- **修正 Browse 工具栏顺序**：新增标签页的 `+` 按钮始终位于右侧操作区，并紧邻下载按钮左边。
- **重新居中中文工作区控件**：“书架 / 浏览”选择器占满可用宽度，较短的中文标签不会再让控件明显偏左。
- **加强正式包启动验证**：打包检查会使用全新偏好设置分别启动打包后的 App 和最终 DMG 内的 App，并要求两者持续稳定运行。
- **完整验证通过**：14 个测试套件中的 51 项自动化测试全部通过，DMG 同时通过完整性与严格代码签名验证。

[查看 MobiVerse 2.4.1 完整发布说明](https://github.com/DemonDevil-Git/MobiVerse/releases/tag/v2.4.1)。

## 产品展示

<p align="center">
  <img src="Docs/product-showcase.png" alt="MobiVerse 2.0 书架界面，使用脱敏示例图书" width="100%">
</p>

## 为什么选择 MobiVerse

- **内置浏览器，便于访问合法阅读来源**
  无需离开 MobiVerse 即可在“书架 / 浏览”之间切换。浏览区支持标签页、持久会话、地址栏收藏和下载托盘；首页不预装或推荐任何电子书网站。

- **完全本地的智能图书分析**
  浏览器下载、文件选择和拖放统一进入“分析 → 确认 → 转换”流程。MobiVerse 会在本地识别文本书、漫画和不确定文件，说明置信度与依据，并允许用户覆盖结果及漫画阅读方向。

- **2.0 全新书架式界面**  
  MobiVerse 2.0 不再是普通工具窗口，而是一个更安静、更有阅读氛围的 macOS 书架工作区：包含拖拽阅读桌、左侧转换统计、精致的图书卡片和暖色视觉风格。

- **为漫画和图像型书籍优化**  
  图像页会被重建为干净的固定布局 EPUB3 页面，减少异常边距、图片拉伸、黑页或翻页尺寸不稳定问题，并写入适合日漫的从右到左阅读元数据。

- **PDF 原生快速转换**
  PDF 漫画不再经过 Calibre 文档重排，而是直接逐页生成固定布局 EPUB，并显示真实页数进度，降低峰值内存占用，同时避免重复重建 EPUB。

- **阅读优先的打开流程**  
  EPUB 可以直接打开预览；MOBI、AZW、漫画压缩包和 PDF 会先在本地转换，然后进入阅读预览。

- **读者无需安装 Calibre**  
  发布版 App 可以内置 Calibre，安装后即可转换支持的文件格式。

- **更适合 Apple Books**  
  MobiVerse 会写入封面元数据、固定布局显示选项和自包含图像页面，让转换后的 EPUB 在 Apple Books 中更稳定。

- **精致的分页 EPUB 阅读器**
  可重排文本会自动适配阅读器窗口，以水平翻页取代上下滚动；漫画会逐页适配窗口并支持水平翻页与缩放。两种模式关闭后重新打开时都会精确恢复阅读位置。

- **完整适配系统外观**
  书架、浏览器、设置、导入确认和阅读器都会适配 macOS 深浅色模式；也可以通过持久化外观菜单主动选择“跟随系统 / 浅色 / 深色”。

- **英文与简体中文界面**
  应用界面完整支持英文与简体中文；语言菜单可跟随 macOS，也可以在应用内直接切换。

- **直接导入 EPUB 书库**
  直接打开的 EPUB 会自动加入书库并提取封面；再次打开同一文件会更新已有项目，不会产生重复记录。

- **真实封面缩略图**  
  转换完成的图书会显示 EPUB 封面，而不是通用文件图标。封面会缓存在本地，重新打开 App 时书架能更快恢复。

- **网格 / 列表 / 交互式 3D 书架**
  可以在视觉化网格、紧凑列表和支持动画直接选书的 3D 书架之间切换。

- **批量转换与历史记录**  
  可以一次拖入多本书，查看转换进度、打开预览、显示输出文件、查看报告，并在重启后保留转换历史。完成列表中只显示标题、状态和完成时间，不暴露完整本地文件路径。

<p align="center">
  <img src="Docs/apple-books-comparison.svg" alt="Apple Books comic layout before and after MobiVerse processing" width="100%">
</p>

## 支持的文件格式

| 格式 | 用途 |
| --- | --- |
| EPUB | 直接在内置预览中打开 |
| MOBI, AZW, AZW3 | 未加 DRM 的 Kindle 风格电子书 |
| CBZ, ZIP | 由有序图片组成的漫画压缩包 |
| CBR | Calibre 可读取的 RAR 漫画压缩包 |
| PDF | 面向 PDF 漫画和图像型文档的原生快速路径 |

MobiVerse 不移除 DRM。受保护或无法读取的文件会被明确标记为转换失败。

## 安装

### macOS

1. 下载最新 DMG：[MobiVerse-2.4.1.dmg](https://github.com/DemonDevil-Git/MobiVerse/releases/latest/download/MobiVerse-2.4.1.dmg)。
2. 打开 `MobiVerse-2.4.1.dmg`。
3. 将 `MobiVerse.app` 拖入 `Applications`；系统提示时替换旧版本。
4. 启动 MobiVerse，把支持的文件拖入窗口，或在 Finder 中选择用 MobiVerse 打开。

当前 macOS 版本为 MobiVerse 2.4.1 (14)，仅支持 Apple Silicon（`arm64`）。

### Windows 11 ARM64

当前 Windows 版本仍为 2.2.0。下载并运行 [MobiVerse-2.2.0-Windows11-ARM64-Setup.exe](https://github.com/DemonDevil-Git/MobiVerse/releases/download/v2.2.0/MobiVerse-2.2.0-Windows11-ARM64-Setup.exe)。安装包包含通过 Windows 11 ARM64 仿真运行的 x64 MobiVerse 与 Calibre 组件，以及原生 ARM64 WebView2 运行时。MobiVerse 2.4.0 目前仅更新 macOS 版本。

转换后的 EPUB 会保存到原文件旁边，并避免覆盖已有 EPUB。

发布版 App 内置 Calibre、EPUBCheck 与运行 EPUBCheck 所需的 Java，因此普通读者不需要额外安装转换和验证依赖。

如果 macOS 提示“Apple 无法验证 MobiVerse”，说明当前 DMG 没有经过 Apple Developer ID 公证。正式公开分发版本后续应使用 Developer ID 签名、公证并 stapled。

## 预览能力

漫画和图像页 EPUB 支持：

- 原生水平翻页
- 全屏预览
- 放大、缩小和适配窗口
- 全屏或窗口尺寸变化后自动重新居中当前页

文本 EPUB 和带插图的文本 EPUB 会加载书脊中的全部可读文档，不再停留在封面。可以通过上一节 / 下一节按钮、水平滑动或章节进度滑块浏览全书。包含正文的插图章节会保持文本阅读模式，不再被误判为纯图片漫画页面。

直接打开 EPUB 时，文件还会加入本地书库、通过现有封面流程提取封面，并在重复打开同一文件时避免生成重复记录。

EPUB 内部文件引用会被限制在书籍解包目录中。文本预览会禁用书籍自带 JavaScript、阻止远程网络资源、限制页面导航，并使用非持久化 WebView 存储。

PDF 转换会把每一页按原始视觉效果保存为固定布局图像，因此 PDF 中可选择的文字、链接、批注和表单不会保留到 EPUB 中。

## 2.4.0 新增内容

- 新增完整简体中文界面，并提供简体中文、English 与跟随 macOS 的应用内语言切换。
- 新增交互式 3D 书架：支持直接点击任意可见书籍、平滑弹簧动画、书籍节点预热、稳定的悬停布局和快速随机切换。
- 正在转换、正在验证以及最新完成的书籍会始终排在书架最前面，不再出现在列表底部。
- Browse 下载时会显示动态活动标识；点击“取消”会立即终止下载并从下载托盘移除。
- 优化大型 EPUB 的封面和元数据加载，无需为填充书架而解压整本书。
- 移除 3D 书籍封面底部重复的绿色完成状态条。
- 新增专项回归验证；当前 14 个测试套件共 51 项测试全部通过。

## 2.3.1 新增内容

- 修复浏览器下载确认后，SwiftUI 导入审核列表可能因生命周期竞态发生闪退的问题。
- 修复漫画 AZW3 转换后的 EPUB 校验：写入必需的修改时间，在 manifest 页面项目上保留 SVG 声明，并从 spine 项目引用中移除无效 SVG 属性。
- Browse 打开的 PDF 响应现在默认进入下载流程，不再被 WebKit 内置 PDF 阅读器接管；支持没有 `.pdf` 后缀的临时签名链接，同时不会误拦截网页内嵌 PDF。
- 新增持久化 PDF 链接设置，可选择自动下载或在浏览器中预览。
- 新增专项回归测试；当前 14 个测试套件共 49 项测试全部通过。

## 2.3.0 新增内容

- 新增 macOS“书架 / 浏览”双工作区。独立 WKWebView 浏览器支持持久登录、标签页、导航、主页、自定义收藏，以及地址栏五角星收藏/取消收藏与下方收藏标签联动。
- 新增下载托盘，支持进度、暂停、取消、重试、重名处理、自定义下载位置和 Finder 定位。文件先暂存，再按签名、MIME、扩展名和真实内容校验；HTML 错误页、可执行文件及伪装格式不会进入转换队列。
- 新增浏览隐私设置，可清除 Cookie、缓存和浏览历史，但不会删除下载图书、转换历史或收藏。EPUB 预览继续使用完全独立的安全 WebView，禁用脚本、联网与持久存储。
- 浏览器下载、文件选择和拖放现已统一进入本地“分析 → 确认 → 转换”流程。批量确认面板会显示文本书/漫画/不确定、置信度与依据，并允许覆盖结果及选择漫画从左到右或从右到左阅读。
- 新增明确的文本可重排与漫画固定布局转换路线。原有漫画 CSS、图片归一化、PDFKit 固定布局、日漫元数据、EPUBCheck 报告、封面缓存、失败重试、预览、Finder 和历史功能保持不变。
- EPUB 输入不再无意义地重新打包，只进行安全解析、类型识别、封面提取并直接加入书架。
- AZW/MOBI 文本书现在强制输出 EPUB 3。转换会保留日语 `<ruby>/<rt>` 注音，并在 EPUBCheck 前自动修复非法 XML ID、失效样式/资源引用和 NCX 目录顺序。
- 文本 EPUB 预览升级为优雅的窗口自适应分页阅读器，支持水平翻页、字体排版、阅读主题，以及精确恢复章节和页码；漫画 EPUB 也会逐页适配窗口、水平翻页并恢复上次页码。
- 新增全局自适应深浅色配色和持久化“跟随系统 / 浅色 / 深色”切换。深色模式左下角静物插图使用高分辨率抗锯齿资源，并与浅色模式保持相同视觉尺寸。
- 正式验证包现在始终内置 Calibre、EPUBCheck 和 EPUBCheck 所需 Java 运行时。
- 保持旧版历史 JSON 兼容；已有任务仍按原漫画配置恢复，不会被重新处理。

## 2.2.1 新增内容

- 修复文本 EPUB 预览只显示封面的问题，现在会加载完整书脊。
- 新增上一节 / 下一节按钮、水平章节导航和章节进度滑块。
- 避免把包含正文的插图章节误判为纯图片漫画页面。
- 直接打开的 EPUB 会加入书库、提取封面，并避免重复记录。

## 2.2.0 新增内容

- 新增 Windows 11 ARM64 桌面版本和 Windows CI。
- 阻止 EPUB 包描述、页面和图片引用中的路径穿越。
- 加固文本 EPUB 预览：禁用 JavaScript、阻止远程资源、限制导航并使用非持久化存储。

## 2.1 新增内容

- 面向 PDF 漫画和图像型书籍的 PDFKit 原生快速路径。
- 显示真实的逐页 PDF 转换进度。
- 逐页渲染并及时释放资源，降低峰值内存占用。
- 不再执行 Calibre PDF 重排和重复 EPUB 重建。
- 实测约 400MB PDF 漫画可在 10 秒内完成转换；实际速度取决于文件结构与硬件。

## 2.0 新增内容

- 全新的暖色书架 UI，包含大面积拖拽区域和阅读主题插画。
- 左侧书架统计：总转换数、成功、失败、进行中。
- 已完成 EPUB 卡片显示提取出的真实封面缩略图。
- 本地封面缓存，避免重新打开 App 后封面再次明显闪现加载。
- 转换书架支持网格 / 列表视图切换。
- 完成卡片不再显示完整源文件路径，界面更干净。
- 打包流程会把 UI 图片资源一并放入 App 和 DMG。

## 路线图

- 签名并公证的公开 DMG。
- 更完善的元数据编辑，包括标题、作者、封面和系列信息。
- 使用同一套跨平台模型、基于 WebView2 的 Windows 浏览工作区。

## 常见问题

### 读者需要安装 Calibre 吗？

不需要。发布版会内置 Calibre，安装 MobiVerse 后即可转换支持的文件。

### MobiVerse 可以移除 DRM 吗？

不可以。MobiVerse 只转换 DRM-free 或系统可读取的文件。受保护文件会被报告为转换失败。

### 为什么 macOS 提示无法验证 App？

当前公开 DMG 还没有经过 Apple Developer ID 公证。公证版本在后续发布计划中。

### 转换后的 EPUB 保存在哪里？

MobiVerse 会把 EPUB 写到原始文件旁边，并避免覆盖已有文件。

### 我的书会上传到服务器吗？

不会。转换完全在你的电脑本地完成。

## 隐私

MobiVerse 在你的电脑本地运行，不会把你的书上传到服务器。

## 开发

### 环境要求

- macOS 14 或更高版本
- Swift 6 / Xcode 26 或更高版本
- 构建发布包的机器需要本地 Calibre App，用于复制进可分发 App 包。默认路径为 `/Applications/calibre.app`；可通过 `CALIBRE_APP=/path/to/calibre.app` 覆盖。
- EPUBCheck 与 OpenJDK，所有验证包和发布包都必须内置。脚本会探测常见 Homebrew 路径，也可通过 `EPUBCHECK_JAR=/path/to/epubcheck.jar` 和 `EPUBCHECK_JAVA_HOME=/path/to/java/home` 指定。

### 从源码运行

```sh
swift run Mobi2EpubTransfer
```

开发运行时，如果是通过 `scripts/package-app.sh` 创建的 App bundle 启动，会优先使用内置 Calibre；否则回退到系统安装的 Calibre。

### 打包 App

```sh
scripts/package-app.sh
```

生成的 App 位于：

```text
.build/MobiVerse.app
```

### 打包 DMG

```sh
scripts/package-dmg.sh
```

生成的安装镜像位于：

```text
.build/MobiVerse-2.4.1.dmg
```

默认开发构建使用 ad-hoc 签名，适合本地测试；但从互联网下载后会被 macOS Gatekeeper 拦截。

### 打包已公证的发布版

公开分发 macOS App 需要 Apple Developer Program 账号、Keychain 中的 `Developer ID Application` 证书，以及 Apple 公证凭据。

先保存公证凭据：

```sh
xcrun notarytool store-credentials mobiverse-notary \
  --apple-id "you@example.com" \
  --team-id "TEAMID" \
  --password "app-specific-password"
```

然后构建发布 DMG：

```sh
SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" \
BUNDLE_IDENTIFIER="com.yourcompany.mobiverse" \
NOTARIZE=1 \
NOTARYTOOL_PROFILE="mobiverse-notary" \
scripts/package-dmg.sh
```

脚本会使用 hardened runtime 和 timestamp 签名 App，签名 DMG，提交 Apple 公证，staple 公证票据，并校验最终 DMG。

### EPUBCheck 要求

```sh
EPUBCHECK_JAR=/path/to/epubcheck.jar scripts/package-dmg.sh
```

两个脚本都会内置 Calibre、EPUBCheck 及其 Java 运行时；缺少任何依赖时都会直接失败，不再生成依赖不完整或无法运行的验证包。

## 测试

```sh
swift test
```

## 许可证

MobiVerse 使用 GPLv3 或更高版本授权。

如果你分发包含 Calibre 的 App bundle，也需要遵守 Calibre GPLv3 对对应 Calibre 版本源码分发的要求。详见 [ThirdPartyNotices.md](ThirdPartyNotices.md)。
