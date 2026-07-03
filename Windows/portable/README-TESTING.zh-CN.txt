MobiVerse 2.2.0 Windows 测试包
================================

目标环境：Windows 11 ARM64。
MobiVerse 和 Calibre 为 x64 程序，由 Windows 11 x64 仿真层运行；WebView2 使用 ARM64 原生运行时。

安装：

1. 将整个解压后的文件夹复制到 Windows 虚拟机本地磁盘。
2. 双击 Install-MobiVerse.cmd。
3. 等待 WebView2 和 MobiVerse 安装完成；Calibre 已直接内置，无需另行安装。
4. 安装完成后 MobiVerse 会自动启动。

安装位置：

%LOCALAPPDATA%\Programs\MobiVerse

注意：

- 安装面向当前 Windows 用户，正常情况下无需管理员权限。
- Windows SmartScreen 可能提示“未知发布者”，因为当前测试包未使用 Authenticode 证书签名。
- MobiVerse 不移除 DRM。
- EPUB、MOBI、AZW、AZW3、CBZ、CBR、ZIP 和 PDF 会出现在“打开方式”列表，但不会替换默认应用。

建议测试：

- EPUB 直接预览，包括文本书和漫画。
- MOBI/AZW/AZW3 转换。
- CBZ/CBR/ZIP 漫画转换。
- PDF 原生逐页转换。
- 网格/列表切换、历史恢复、封面、报告、输出定位和删除。
- 键盘翻页、缩放、全屏以及阅读位置恢复。

卸载：

从开始菜单运行 “Uninstall MobiVerse”，或在 Windows 设置的“已安装的应用”中卸载。
