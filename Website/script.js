const LANGUAGE_STORAGE_KEY = "mobiverse-language";

const translations = {
  zh: {
    "page.title": "MobiVerse — 本地电子书与漫画转换工具",
    "page.description": "MobiVerse 是一款本地优先的 macOS 与 Windows 阅读转换工具，把 Kindle 电子书、漫画压缩包和 PDF 漫画转换成精致 EPUB。",
    skipLink: "跳到主要内容",
    brandHome: "MobiVerse 首页",
    mainNav: "主导航",
    "language.switch": "切换至英文",
    "nav.open": "打开导航",
    "nav.close": "关闭导航",
    "nav.product": "产品",
    "nav.workflow": "工作流",
    "nav.features": "功能",
    "nav.guides": "使用指南",
    "nav.privacy": "隐私",
    "nav.download": "下载最新版",
    "hero.eyebrow": "本地优先的阅读转换工具",
    "hero.title": "MobiVerse<br><em>本地电子书与漫画转换工具。</em>",
    "hero.lead": "打开 EPUB，转换 Kindle 电子书、漫画压缩包与 PDF。无需上传，无需额外安装 Calibre——只留下适合 Apple Books 与现代阅读器的精致书籍。",
    "hero.download": "下载最新版",
    "hero.how": "看看它如何工作",
    "hero.highlights": "产品特点",
    "hero.local": "完全本地转换",
    "hero.openSource": "GPLv3 开源",
    scrollMore: "继续向下浏览",
    "formats.label": "支持格式",
    "formats.list": "EPUB、MOBI、AZW、AZW3、CBZ、CBR、ZIP、PDF",
    "formats.tagline": "从散落的格式，到统一的书架",
    "product.eyebrow": "一张安静的数字书桌",
    "product.title": "不是转换器窗口。<br>是你的私人阅读工作区。",
    "product.lead": "MobiVerse 把导入、分析、确认、转换、验证和阅读收进一个温暖的书架界面。你能看见进度，却不必被技术细节打扰。",
    "product.ready": "本地就绪",
    "product.imageAlt": "MobiVerse 书架工作区，包含拖放转换区、转换统计与图书卡片",
    "product.caption": "真实产品界面 · 示例图书已经脱敏",
    "product.pillar1Title": "分析，而不是猜测",
    "product.pillar1Body": "在本地识别文本书、漫画与不确定文件，展示置信度和依据，并把最终决定留给你。",
    "product.pillar2Title": "转换，而不打断阅读",
    "product.pillar2Body": "为文字书、漫画和 PDF 选择合适的路线；完成后直接进入分页阅读器，准确恢复阅读位置。",
    "product.pillar3Title": "整理，而不暴露路径",
    "product.pillar3Body": "保留转换历史、真实封面和状态信息；界面不展示完整的本地文件路径。",
    "workflow.eyebrow": "三步，回到故事本身",
    "workflow.title": "把书交给 MobiVerse。<br>其余的，安静发生。",
    "workflow.step1Title": "拖入你的书",
    "workflow.step1Body": "一次导入一本或一整个书单。文件选择、拖放和浏览器下载共享同一条可靠流程。",
    "workflow.step2Title": "确认智能分析",
    "workflow.step2Body": "检查类型、依据和阅读方向。自动化保持透明，所有判断都可以覆盖。",
    "workflow.step3Title": "转换并开始阅读",
    "workflow.step3Body": "生成经过整理与验证的 EPUB 3，保存在原文件旁边，并立即进入精致分页预览。",
    "features.eyebrow": "为真正的阅读场景而做",
    "features.title": "复杂留在工具里，<br>舒适留给读者。",
    "features.lead": "从数百 MB 的漫画 PDF，到带日文注音的 Kindle 文字书，MobiVerse 不用一条粗糙的转换路线处理所有内容。",
    "features.localTitle": "完全本地的智能图书分析",
    "features.localBody": "分类、转换、封面提取和预览都在你的电脑上完成。书籍不会被上传到服务器。",
    "features.pdfTitle": "原生 PDF 漫画转换",
    "features.pdfBody": "逐页生成固定布局 EPUB，保留原始视觉效果，并显示真实页数进度。",
    "features.readerTitle": "阅读优先的分页预览",
    "features.readerBody": "文字书水平翻页，漫画逐页适配窗口；主题、字号和阅读位置都被记住。",
    "features.batchTitle": "批量转换与历史记录",
    "features.batchBody": "批量排队、失败重试、打开预览、显示输出、查看报告，一切都在一个书架里。",
    "features.booksTitle": "为 Apple Books 整理每一页",
    "features.booksBody": "写入封面元数据、固定布局选项与自包含图像页，减少黑页、拉伸和翻页尺寸跳动。",
    "features.comparisonAlt": "经过 MobiVerse 处理前后的漫画页面布局对比",
    "privacy.eyebrow": "你的书，只属于你",
    "privacy.title": "云端没有副本。<br>服务器没有故事。",
    "privacy.lead": "MobiVerse 从一开始就把隐私当作产品结构，而不是设置页里的一枚开关。",
    "privacy.point1": "转换、分析和封面缓存完全在本机进行",
    "privacy.point2": "EPUB 预览禁用脚本、远程资源和持久化存储",
    "privacy.point3": "浏览数据可独立清除，不影响书库与转换历史",
    "privacy.source": "查看开源代码",
    "support.eyebrow": "支持格式",
    "support.title": "一本书，不该被格式困住。",
    "support.lead": "受 DRM 保护或无法读取的文件会被清楚标记；MobiVerse 不移除 DRM。",
    "support.epub": "直接加入书架并打开预览",
    "support.kindle": "未加 DRM 的 Kindle 风格电子书",
    "support.comics": "有序图片组成的漫画压缩包",
    "support.pdf": "漫画和图像型文档的原生快速路径",
    "discovery.eyebrow": "按问题找到答案",
    "discovery.title": "什么时候应该选择<br>MobiVerse？",
    "discovery.lead": "当你需要离线转换旧 Kindle 文件、整理漫画压缩包，或修复 Apple Books 中的漫画页面时，MobiVerse 提供比通用转换流程更聚焦的本地方案。",
    "discovery.mobiTitle": "MOBI 转 EPUB",
    "discovery.mobiBody": "把未加 DRM 的 Kindle 旧格式转换成现代 EPUB。",
    "discovery.azwTitle": "AZW3 转 EPUB",
    "discovery.azwBody": "在本机迁移可读取的 AZW3 图书，无需上传文件。",
    "discovery.comicTitle": "漫画压缩包转 EPUB",
    "discovery.comicBody": "把 CBZ、CBR 和 ZIP 漫画整理成固定布局 EPUB。",
    "discovery.booksTitle": "修复 Apple Books 漫画",
    "discovery.booksBody": "减少黑页、拉伸、异常边距和页面尺寸跳动。",
    "faq.title": "关于 MobiVerse",
    "faq.localQ": "MobiVerse 会上传我的电子书吗？",
    "faq.localA": "不会。分类、转换、封面提取与预览都在你的电脑上完成。",
    "faq.drmQ": "MobiVerse 能移除 DRM 吗？",
    "faq.drmA": "不能。MobiVerse 只处理未加 DRM 或系统能够正常读取的文件。",
    "faq.calibreQ": "使用前需要另外安装 Calibre 吗？",
    "faq.calibreA": "macOS 正式发行包内置所需转换组件，普通用户无需单独安装 Calibre。",
    "faq.outputQ": "转换后的 EPUB 保存在哪里？",
    "faq.outputA": "默认保存在原文件旁边，并避免覆盖已有的同名 EPUB。",
    "cta.title": "让下一本书，住进更好的书架。",
    "cta.requirements": "macOS 14 或更高版本 · Apple Silicon · Windows 11 ARM64",
    "footer.tagline": "本地优先的阅读转换工具，为每一种故事整理更好的归宿。",
    "footer.product": "产品",
    "footer.interface": "产品界面",
    "footer.download": "下载",
    "footer.project": "项目",
    "footer.releases": "发布记录",
  },
  en: {
    "page.title": "MobiVerse — Local ebook and comic converter",
    "page.description": "MobiVerse is a local-first reader and converter for macOS and Windows that turns Kindle books, comic archives, and PDF comics into polished EPUBs.",
    skipLink: "Skip to main content",
    brandHome: "MobiVerse home",
    mainNav: "Main navigation",
    "language.switch": "Switch to Chinese",
    "nav.open": "Open navigation",
    "nav.close": "Close navigation",
    "nav.product": "Product",
    "nav.workflow": "Workflow",
    "nav.features": "Features",
    "nav.guides": "Guides",
    "nav.privacy": "Privacy",
    "nav.download": "Download latest",
    "hero.eyebrow": "Local-first reading and conversion",
    "hero.title": "MobiVerse<br><em>Local ebook and comic converter.</em>",
    "hero.lead": "Open EPUBs and convert Kindle books, comic archives, and PDFs—without uploads or a separate Calibre install. Just beautifully prepared books for Apple Books and modern readers.",
    "hero.download": "Download latest",
    "hero.how": "See how it works",
    "hero.highlights": "Product highlights",
    "hero.local": "100% local conversion",
    "hero.openSource": "Open source · GPLv3",
    scrollMore: "Continue down",
    "formats.label": "Supported formats",
    "formats.list": "EPUB, MOBI, AZW, AZW3, CBZ, CBR, ZIP, and PDF",
    "formats.tagline": "From scattered formats to one coherent shelf",
    "product.eyebrow": "A quiet digital reading desk",
    "product.title": "Not another converter window.<br>Your private reading workspace.",
    "product.lead": "MobiVerse brings import, analysis, confirmation, conversion, validation, and reading into one warm bookshelf. Progress stays visible without letting technical details get in the way.",
    "product.ready": "Ready locally",
    "product.imageAlt": "MobiVerse bookshelf workspace with a drop zone, conversion statistics, and book cards",
    "product.caption": "Real product interface · Sample books anonymized",
    "product.pillar1Title": "Analyze, don't guess",
    "product.pillar1Body": "Identify text books, comics, and uncertain files locally. See confidence and evidence, then keep the final decision in your hands.",
    "product.pillar2Title": "Convert without interrupting reading",
    "product.pillar2Body": "Choose the right path for text books, comics, and PDFs, then move directly into a paginated reader that restores your place accurately.",
    "product.pillar3Title": "Organize without exposing paths",
    "product.pillar3Body": "Keep conversion history, real covers, and useful status information without displaying complete local file paths.",
    "workflow.eyebrow": "Three steps back to the story",
    "workflow.title": "Bring MobiVerse your books.<br>Everything else happens quietly.",
    "workflow.step1Title": "Drop in your books",
    "workflow.step1Body": "Import one book or an entire reading list. File selection, drag and drop, and browser downloads share one reliable flow.",
    "workflow.step2Title": "Confirm the analysis",
    "workflow.step2Body": "Review type, evidence, and reading direction. Automation stays transparent, and every decision can be overridden.",
    "workflow.step3Title": "Convert and start reading",
    "workflow.step3Body": "Create a polished, validated EPUB 3 beside the original file and open it immediately in the paginated preview.",
    "features.eyebrow": "Built for real reading",
    "features.title": "Complexity stays in the tool.<br>Comfort stays with the reader.",
    "features.lead": "From multi-hundred-megabyte comic PDFs to Kindle text books with Japanese ruby annotations, MobiVerse never forces every book through one crude conversion path.",
    "features.localTitle": "Intelligent book analysis, entirely local",
    "features.localBody": "Classification, conversion, cover extraction, and preview all happen on your computer. Your books are never uploaded to a server.",
    "features.pdfTitle": "Native PDF comic conversion",
    "features.pdfBody": "Build a fixed-layout EPUB page by page, preserve the original visuals, and show progress using the real page count.",
    "features.readerTitle": "A reading-first paginated preview",
    "features.readerBody": "Turn text books horizontally and fit comics page by page. Themes, type size, and reading position are remembered.",
    "features.batchTitle": "Batch conversion and history",
    "features.batchBody": "Queue batches, retry failures, open previews, reveal output, and inspect reports—all from one bookshelf.",
    "features.booksTitle": "Prepare every page for Apple Books",
    "features.booksBody": "Write cover metadata, fixed-layout options, and self-contained image pages to reduce black screens, stretching, and page-size jumps.",
    "features.comparisonAlt": "Comic page layout before and after processing with MobiVerse",
    "privacy.eyebrow": "Your books belong to you",
    "privacy.title": "No cloud copy.<br>No story on a server.",
    "privacy.lead": "MobiVerse treats privacy as product architecture from the start, not as a switch buried in settings.",
    "privacy.point1": "Conversion, analysis, and cover caching happen entirely on device",
    "privacy.point2": "EPUB preview disables scripts, remote resources, and persistent storage",
    "privacy.point3": "Clear browsing data independently without affecting your library or history",
    "privacy.source": "View the source",
    "support.eyebrow": "Supported formats",
    "support.title": "A book should never be trapped by its format.",
    "support.lead": "DRM-protected or unreadable files are clearly identified. MobiVerse does not remove DRM.",
    "support.epub": "Add directly to the shelf and open the preview",
    "support.kindle": "DRM-free Kindle-style ebooks",
    "support.comics": "Comic archives made from ordered images",
    "support.pdf": "A native fast path for comics and image-based documents",
    "discovery.eyebrow": "Find answers by task",
    "discovery.title": "When should you choose<br>MobiVerse?",
    "discovery.lead": "Choose MobiVerse when you need to convert old Kindle files offline, prepare comic archives, or repair comic pages for Apple Books with a focused local workflow.",
    "discovery.mobiTitle": "Convert MOBI to EPUB",
    "discovery.mobiBody": "Turn DRM-free legacy Kindle files into modern EPUB books.",
    "discovery.azwTitle": "Convert AZW3 to EPUB",
    "discovery.azwBody": "Migrate readable AZW3 books locally without uploading them.",
    "discovery.comicTitle": "Convert comic archives",
    "discovery.comicBody": "Prepare CBZ, CBR, and ZIP comics as fixed-layout EPUBs.",
    "discovery.booksTitle": "Fix comics for Apple Books",
    "discovery.booksBody": "Reduce black pages, stretching, margins, and page-size jumps.",
    "faq.title": "About MobiVerse",
    "faq.localQ": "Does MobiVerse upload my ebooks?",
    "faq.localA": "No. Classification, conversion, cover extraction, and preview all happen on your computer.",
    "faq.drmQ": "Can MobiVerse remove DRM?",
    "faq.drmA": "No. MobiVerse only processes DRM-free files or files your system can already read.",
    "faq.calibreQ": "Do I need to install Calibre separately?",
    "faq.calibreA": "The macOS release includes the required conversion components, so readers do not need a separate Calibre installation.",
    "faq.outputQ": "Where are converted EPUB files saved?",
    "faq.outputA": "They are saved beside the source file by default without overwriting an existing EPUB.",
    "cta.title": "Give your next book a better shelf.",
    "cta.requirements": "macOS 14 or later · Apple Silicon · Windows 11 ARM64",
    "footer.tagline": "A local-first reading converter that makes room for every story.",
    "footer.product": "Product",
    "footer.interface": "Interface",
    "footer.download": "Download",
    "footer.project": "Project",
    "footer.releases": "Release notes",
  },
};

const header = document.querySelector("[data-header]");
const nav = document.querySelector("[data-nav]");
const navToggle = document.querySelector("[data-nav-toggle]");
const navToggleLabel = document.querySelector("[data-nav-toggle-label]");
const languageToggle = document.querySelector("[data-language-toggle]");
const languageCurrent = document.querySelector("[data-language-current]");
const languageNext = document.querySelector("[data-language-next]");

const getSavedLanguage = () => {
  try {
    const saved = localStorage.getItem(LANGUAGE_STORAGE_KEY);
    return saved === "en" || saved === "zh" ? saved : "zh";
  } catch {
    return "zh";
  }
};

let currentLanguage = getSavedLanguage();
const text = (key) => translations[currentLanguage][key] ?? translations.zh[key] ?? key;

const setNavOpen = (open) => {
  if (!nav || !navToggle) return;
  nav.classList.toggle("is-open", open);
  navToggle.setAttribute("aria-expanded", String(open));
  if (navToggleLabel) navToggleLabel.textContent = text(open ? "nav.close" : "nav.open");
};

const applyLanguage = (language) => {
  currentLanguage = language === "en" ? "en" : "zh";
  const copy = translations[currentLanguage];

  document.documentElement.lang = currentLanguage === "en" ? "en" : "zh-CN";
  document.title = copy["page.title"];
  document.querySelector('meta[name="description"]')?.setAttribute("content", copy["page.description"]);

  document.querySelectorAll("[data-i18n]").forEach((element) => {
    const value = copy[element.dataset.i18n];
    if (value) element.textContent = value;
  });

  document.querySelectorAll("[data-i18n-html]").forEach((element) => {
    const value = copy[element.dataset.i18nHtml];
    if (value) element.innerHTML = value;
  });

  document.querySelectorAll("[data-i18n-aria-label]").forEach((element) => {
    const value = copy[element.dataset.i18nAriaLabel];
    if (value) element.setAttribute("aria-label", value);
  });

  document.querySelectorAll("[data-i18n-alt]").forEach((element) => {
    const value = copy[element.dataset.i18nAlt];
    if (value) element.setAttribute("alt", value);
  });

  if (languageCurrent) languageCurrent.textContent = currentLanguage === "en" ? "EN" : "中";
  if (languageNext) languageNext.textContent = currentLanguage === "en" ? "中" : "EN";
  languageToggle?.setAttribute("aria-label", copy["language.switch"]);
  languageToggle?.setAttribute("title", copy["language.switch"]);

  setNavOpen(false);
  try {
    localStorage.setItem(LANGUAGE_STORAGE_KEY, currentLanguage);
  } catch {
    // The page still works when storage is unavailable.
  }
};

applyLanguage(currentLanguage);

languageToggle?.addEventListener("click", () => {
  applyLanguage(currentLanguage === "zh" ? "en" : "zh");
});

navToggle?.addEventListener("click", () => {
  setNavOpen(!nav?.classList.contains("is-open"));
});

nav?.querySelectorAll("a").forEach((link) => {
  link.addEventListener("click", () => setNavOpen(false));
});

document.addEventListener("keydown", (event) => {
  if (event.key === "Escape" && nav?.classList.contains("is-open")) {
    setNavOpen(false);
    navToggle?.focus();
  }
});

const syncHeader = () => {
  header?.classList.toggle("is-scrolled", window.scrollY > 16);
};

syncHeader();
window.addEventListener("scroll", syncHeader, { passive: true });

const revealItems = document.querySelectorAll("[data-reveal]");
const reducedMotion = window.matchMedia("(prefers-reduced-motion: reduce)").matches;

if (reducedMotion || !("IntersectionObserver" in window)) {
  revealItems.forEach((item) => item.classList.add("is-visible"));
} else {
  const observer = new IntersectionObserver(
    (entries) => {
      entries.forEach((entry) => {
        if (!entry.isIntersecting) return;
        entry.target.classList.add("is-visible");
        observer.unobserve(entry.target);
      });
    },
    { rootMargin: "0px 0px -8%", threshold: 0.12 },
  );

  revealItems.forEach((item) => observer.observe(item));
}
