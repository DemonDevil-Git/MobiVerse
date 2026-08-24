MobiVerse 2.3.1 (Build 12) Windows 免安装便携测试版 R2
======================================================

R2 修复：顶部主视觉图片、便携数据隔离、卡片按钮点击识别。

目标环境：Windows 11 ARM64。
MobiVerse、Calibre 和内置 WebView2 为 x64 程序，由 Windows 11 x64 仿真层运行。

启动：

1. 将 ZIP 完整解压到本地磁盘，例如“下载\MobiVerse-2.3.1-Portable”。
2. 不要在 ZIP 预览窗口内运行，也不要只复制 MobiVerse.exe。
3. 双击 MobiVerse.exe；不需要安装，不需要管理员权限。
4. 若 SmartScreen 提示“未知发布者”，选择“更多信息”→“仍要运行”。

请按以下顺序测试：

1. 书架与导入确认
   - “Shelf / Browse”可以正常切换。
   - 选择或拖入 EPUB、MOBI、AZW、AZW3、CBZ、CBR、ZIP、PDF。
   - 导入确认窗口会显示本地内容识别结果；不确定项目必须手动选择“文本”或“漫画”。
   - 漫画可以选择从右向左或从左向右。
   - 取消确认后，可通过左侧“Review imports”继续。

2. 转换与校验
   - 文本书生成 EPUB 3，并保留 ruby 注音等语义内容。
   - 漫画和扫描 PDF 生成固定版式 EPUB。
   - 检查 MOBI/AZW/AZW3、CBZ/CBR/ZIP、文本 PDF、扫描 PDF。
   - 完成后检查封面、EPUBCheck 报告、输出定位、失败重试和删除。

3. 阅读器
   - EPUB 可直接加入书架并打开，不发生重复转换。
   - 文本 EPUB 可跨章节逐页阅读；Paper、Sepia、Night 主题、字号和行距立即生效。
   - 关闭后重新打开，应恢复文本书的章节和页码。
   - 漫画可翻页、拖动进度、缩放、适配窗口、全屏，并恢复页码。
   - 左右方向键、鼠标滚轮和 Ctrl+滚轮可用。

4. 内置浏览器
   - 新建/关闭/切换标签页，测试前进、后退、刷新、主页和地址搜索。
   - 添加、打开和删除书签。
   - 下载 EPUB/MOBI/AZW/AZW3/CBZ/CBR/ZIP/PDF；完成后自动进入导入确认。
   - 下载列表可暂停、继续、取消和定位文件；自定义下载目录可保存。
   - 开启“Automatically download main-page PDFs”后，主页面 PDF（包括无 .pdf 后缀的临时链接）自动下载。
   - 关闭该设置后 PDF 在浏览器中预览；网页内嵌 PDF 不应被强制下载。
   - “Clear browsing data”可以清除 Cookie、缓存、权限和浏览历史。

5. 外观与持久化
   - System、Light、Dark 三种应用外观可切换并记住。
   - 重启后书架、转换记录、待确认导入、浏览器书签、下载目录、PDF 设置和阅读器设置仍保留。

已知提示：

- 当前便携版未使用 Authenticode 证书签名，因此可能显示 SmartScreen 警告。
- 请保留 MobiVerse.exe、全部 DLL、Resources、Xaml 和 ThirdParty 的相对目录结构。
- 请从本地磁盘运行；内置 WebView2 固定版不支持从网络共享或 UNC 路径运行。
- MobiVerse 不移除 DRM。
- 若某一步失败，请保留错误截图、输入文件类型，以及：
  %LOCALAPPDATA%\MobiVerse\Portable\Logs

移除：

关闭 MobiVerse 后删除解压出的程序文件夹即可。
如需同时清除书架、历史、设置和浏览数据，再手动删除：
%LOCALAPPDATA%\MobiVerse\Portable
