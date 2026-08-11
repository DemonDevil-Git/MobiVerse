# MobiVerse

> 中文说明：[README.zh-CN.md](README.zh-CN.md)

**A local-first macOS and Windows reader-converter for opening EPUBs directly and turning Kindle books, comic archives, and PDF comics into polished EPUBs for Apple Books and modern EPUB readers.**

<p align="center">
  <img src="Docs/hero.svg" alt="MobiVerse converts illustrated books into Apple Books-friendly EPUBs" width="100%">
</p>

<p align="center">
  <a href="https://github.com/DemonDevil-Git/MobiVerse/releases/latest/download/MobiVerse-2.4.1.dmg"><img src="https://img.shields.io/badge/macOS%202.4.1-Download-1764D8?style=for-the-badge&logo=apple&logoColor=white" alt="Download MobiVerse 2.4.1 for macOS"></a>
  <a href="https://github.com/DemonDevil-Git/MobiVerse/releases/download/v2.2.0/MobiVerse-2.2.0-Windows11-ARM64-Setup.exe"><img src="https://img.shields.io/badge/Windows%202.2.0-Download-1764D8?style=for-the-badge&logo=windows11&logoColor=white" alt="Download MobiVerse 2.2.0 for Windows"></a>
  <a href="https://github.com/DemonDevil-Git/MobiVerse/releases"><img src="https://img.shields.io/github/v/release/DemonDevil-Git/MobiVerse?style=for-the-badge&label=Latest%20release" alt="Latest release"></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/License-GPLv3-111827?style=for-the-badge" alt="GPLv3 license"></a>
</p>

<p align="center">
  <strong>No Calibre installation required for readers.</strong> Best for manga, illustrated Kindle books, comic archives, and Apple Books-friendly EPUB output.
</p>

## Product Demo

https://github.com/user-attachments/assets/485accd5-569d-45ed-b25f-5643ba96d3fc

Watch the [web demo](https://mobiverse-coral.vercel.app/#demo), or download the official [H.264 MP4](https://github.com/DemonDevil-Git/MobiVerse/releases/download/v2.4.1/MobiVerse-2.4.1-Demo.mp4) and [original HEVC MOV](https://github.com/DemonDevil-Git/MobiVerse/releases/download/v2.4.1/MobiVerse-2.4.1-Demo-Original.mov) from GitHub Releases.

## What's New in MobiVerse 2.4.1

Released on August 11, 2026, MobiVerse 2.4.1 (14) is a macOS reliability and workspace-layout update:

- **Reliable first launch for new installations** — packaged localization resources now resolve from their installed location, fixing the crash that could occur the first time a new user opened the app.
- **Correct Browse toolbar order** — the new-tab `+` button stays in the trailing action area immediately to the left of Downloads.
- **Centered Chinese workspace control** — the Shelf/Browse selector fills its available width so the shorter Simplified Chinese labels no longer pull it visibly left.
- **Stronger release validation** — packaging checks now launch both the packaged app and the app inside the final mounted DMG with fresh preferences and require a sustained stability window.
- **Verified release** — 51 automated tests passed across 14 suites; the DMG also passed integrity and strict code-signature verification.

[Read the complete MobiVerse 2.4.1 release notes](https://github.com/DemonDevil-Git/MobiVerse/releases/tag/v2.4.1).

## Product Showcase

<p align="center">
  <img src="Docs/product-showcase.png" alt="MobiVerse 2.0 bookshelf interface with sanitized sample books" width="100%">
</p>

## Why MobiVerse

- **A private, built-in browser for finding legal reading sources**
  Switch between Shelf and Browse without leaving MobiVerse. Browse with tabs and persistent sessions, manage bookmarks from the address bar, and monitor validated downloads in a dedicated tray. No ebook site is promoted or preinstalled.

- **Local intelligent book analysis**
  Browser downloads, file-picker imports, and drag-and-drop files share one analyze → review → convert flow. MobiVerse classifies text books, comics, and uncertain files locally, explains its confidence, and always lets you override the result and comic reading direction.

- **A calmer 2.0 library workspace**  
  MobiVerse 2.0 replaces the plain utility layout with a warm macOS bookshelf interface, a clear drag-and-drop reading desk, sidebar conversion stats, and polished conversion cards.

- **Made for comics and illustrated books**  
  Image pages are rebuilt into clean fixed-layout EPUB3 pages with stable sizing, no unexpected margins, and right-to-left manga metadata.

- **Fast native PDF conversion**
  PDF comics bypass Calibre reflow and render directly into a fixed-layout EPUB with real per-page progress, lower peak memory use, and no duplicate EPUB rebuild.

- **Read-first opening flow**
  Open an EPUB instantly, or open MOBI/AZW/comic/PDF sources and let MobiVerse quietly convert them before showing the preview.

- **Works without asking readers to install Calibre**  
  The distributable app can bundle Calibre so conversion works immediately after installation.

- **Apple Books friendly**  
  MobiVerse writes cover metadata, fixed-layout display options, and self-contained image pages to avoid stretched or black pages.

- **A polished, paginated EPUB reader**
  Reflowable books adapt each page to the reader viewport and turn horizontally instead of requiring vertical scrolling. Comics are fitted page-by-page with native horizontal navigation and zoom. Both modes restore the exact reading position when reopened.

- **System-aware appearance**
  The complete Shelf, Browse, settings, review, and reader interface adapts to macOS light and dark appearances. A persistent appearance menu lets you follow the system or choose Light or Dark manually.

- **English and Simplified Chinese interface**
  The full app interface is localized in English and Simplified Chinese. A persistent language menu can follow macOS or switch languages directly.

- **Direct EPUB library import**
  EPUBs opened directly are added to the library with extracted cover artwork. Reopening the same file updates the existing item instead of creating a duplicate.

- **Real cover thumbnails**  
  Completed books show the converted EPUB cover in the shelf instead of generic file tiles. Covers are cached locally so reopened sessions restore the shelf quickly.

- **Grid, list, and interactive 3D shelf views**
  Switch between a visual grid, a denser list, and a responsive 3D bookshelf with animated direct book selection.

- **Batch conversion with history**  
  Drag in multiple books, track progress, reveal outputs, open reports, and keep conversion history across launches. The completed list keeps titles and status visible without exposing full local file paths in the UI.

<p align="center">
  <img src="Docs/apple-books-comparison.svg" alt="Apple Books comic layout before and after MobiVerse processing" width="100%">
</p>

## Supported Files

| Format | Use case |
| --- | --- |
| EPUB | Open directly in the built-in preview |
| MOBI, AZW, AZW3 | Kindle-style ebooks without DRM |
| CBZ, ZIP | Comic archives made from ordered image files |
| CBR | RAR-based comic archives readable by Calibre |
| PDF | Native fast path for PDF comics and image-heavy documents |

MobiVerse does not remove DRM. Protected or unreadable files are reported clearly.

## Install

### macOS

1. Download the latest DMG: [MobiVerse-2.4.1.dmg](https://github.com/DemonDevil-Git/MobiVerse/releases/latest/download/MobiVerse-2.4.1.dmg).
2. Open `MobiVerse-2.4.1.dmg`.
3. Drag `MobiVerse.app` into `Applications`, replacing the previous version when prompted.
4. Launch MobiVerse and drop supported files into the window, or open supported files with MobiVerse from Finder.

The current macOS release is MobiVerse 2.4.1 (14) for Apple Silicon (`arm64`) only.

### Windows 11 ARM64

The current Windows release remains 2.2.0. Download and run [MobiVerse-2.2.0-Windows11-ARM64-Setup.exe](https://github.com/DemonDevil-Git/MobiVerse/releases/download/v2.2.0/MobiVerse-2.2.0-Windows11-ARM64-Setup.exe). The package includes the x64 MobiVerse and Calibre components used through Windows 11 ARM64 emulation, plus the native ARM64 WebView2 runtime. MobiVerse 2.4.0 is currently a macOS-only update.

Converted EPUB files are written next to the original source file without overwriting existing EPUBs.

The release app bundles Calibre, EPUBCheck, and a Java runtime, so readers do not need to install validation or conversion dependencies separately.

If macOS shows an "Apple could not verify MobiVerse" warning, that DMG was built without Apple Developer ID notarization. Public releases should be signed, notarized, and stapled before upload.

## Preview

Comic and image-page EPUBs support:

- native horizontal page swiping
- fullscreen preview
- zoom in, zoom out, and fit controls
- current-page recentering after fullscreen/window size changes

Text and illustrated-text EPUBs load every readable document in the book spine instead of stopping at the cover. Use the previous/next controls, horizontal swipes, or the section progress slider to move through the book. Illustrated chapters containing real text remain in text-reading mode instead of being mistaken for image-only comic pages.

Opening an EPUB directly also adds it to the local library, extracts its cover through the existing cover pipeline, and avoids duplicate records when the same file is reopened.

EPUB file references are confined to the extracted book directory. Text previews disable book-provided JavaScript, block remote web resources, restrict navigation, and use non-persistent WebView storage.

PDF conversion preserves each page visually as a fixed-layout image. Selectable PDF text, links, annotations, and forms are not retained in the EPUB output.

## What's New in 2.4.0

- Added a complete Simplified Chinese interface and an in-app language selector for Simplified Chinese, English, or the macOS system language.
- Added an interactive 3D shelf with direct book selection, smooth spring transitions, prewarmed book nodes, stable hover geometry, and responsive random access across the visible spines.
- The newest converting, validating, and completed books now stay at the front of the shelf instead of appearing at the bottom.
- Browse now shows animated download activity, and Cancel immediately stops and removes active downloads from the tray.
- Optimized cover and metadata loading so large EPUB libraries no longer require full-archive extraction merely to populate the shelf.
- Removed the redundant green completion strip from the bottom of 3D book covers.
- Added focused regression coverage; 51 automated tests pass across 14 suites.

## What's New in 2.3.1

- Fixed a SwiftUI import-review race that could crash after confirming a browser download.
- Fixed comic AZW3 conversion validation by writing the required EPUB modification timestamp, keeping SVG declarations on manifest items, and removing invalid SVG properties from spine item references.
- PDF responses opened from Browse now download automatically instead of being captured by WebKit's inline PDF viewer. Signed URLs without a `.pdf` suffix are supported, while embedded PDF frames remain viewable.
- Added a persistent Browse setting for choosing automatic PDF downloads or in-browser preview.
- Added focused regression coverage; 49 automated tests now pass across 14 suites.

## What's New in 2.3.0

- Added a macOS Shelf/Browse workspace with a persistent, isolated WKWebView browser, tabs, navigation controls, a start page, user-managed bookmarks, and bookmark-star toggling with an address-bar bookmark strip.
- Added a download tray with progress, pause, cancel, retry, duplicate-name handling, configurable download location, and Finder reveal. Downloads are staged and checked by signature, MIME type, extension, and content; HTML error pages, executables, and disguised unsupported files are rejected.
- Added browser privacy settings for clearing cookies, cache, and browsing history without removing downloaded books, conversion history, or bookmarks. EPUB preview remains a separate locked-down, non-persistent WebView with scripts and network access blocked.
- Unified browser downloads, file selection, and drag-and-drop into a local analyze → review → convert flow. The review sheet shows text/comic/uncertain classification, confidence and evidence, supports batch review and user overrides, and provides left-to-right or right-to-left comic direction.
- Added explicit text-reflow and comic-fixed-layout conversion routes. Existing comic CSS, image normalization, PDFKit fixed-layout conversion, manga metadata, EPUBCheck reporting, cover caching, retry, preview, Finder, and history behaviors are preserved.
- EPUB inputs now pass through safe parsing, classification, cover extraction, and direct shelf import without unnecessary repackaging.
- Text AZW/MOBI conversions now target EPUB 3. Japanese ruby annotations are preserved while invalid XML IDs, broken stylesheet/resource references, and NCX play order are repaired automatically before EPUBCheck validation.
- Redesigned text EPUB preview as a refined viewport-fitted paginated reader with horizontal page turning, typography controls, reading themes, and exact section/page restoration. Comic EPUBs now use fitted horizontal pages and also restore the previous page.
- Added a complete adaptive light/dark palette plus a persistent System/Light/Dark appearance control. The dark-mode reading still-life artwork is high resolution and normalized to the same visual size as the light artwork.
- Release packages now always include Calibre, EPUBCheck, and the Java runtime required to run EPUBCheck.
- Kept existing task history backward-compatible; older task JSON continues to decode with its original comic conversion behavior and does not trigger reprocessing.

## What's New in 2.2.1

- Fixed text EPUB preview so the complete spine loads instead of stopping at the cover.
- Added previous/next section controls, horizontal section navigation, and a section progress slider.
- Prevented illustrated text chapters from being mistaken for image-only comic pages.
- Added directly opened EPUBs to the library with cover extraction and duplicate prevention.

## What's New in 2.2.0

- Added the Windows 11 ARM64 desktop release and Windows CI.
- Blocked EPUB path traversal through package, page, and image references.
- Hardened text EPUB previews by disabling JavaScript, blocking remote resources, restricting navigation, and using non-persistent storage.

## What's New in 2.1

- Native PDFKit fast path for PDF comics and image-heavy books.
- Real page-by-page PDF conversion progress.
- Lower peak memory use through sequential page rendering.
- No Calibre PDF reflow or duplicate EPUB rebuild.
- User-verified conversion of a roughly 400MB PDF comic in under 10 seconds; actual performance varies by file and hardware.

## What's New in 2.0

- Redesigned warm bookshelf UI with a large visual drop zone and reading-inspired artwork.
- Sidebar shelf summary for total conversions, successes, failures, and active jobs.
- Completed EPUB cards now show extracted cover thumbnails.
- Local thumbnail cache prevents already-loaded covers from flashing in on every relaunch.
- Grid/list view switcher for the conversion shelf.
- Cleaner completed-book cards that omit full source file paths.
- Packaged image resources are included in app bundles and DMG builds.

## Roadmap

- Signed and notarized public DMG.
- Better metadata editing for title, author, cover, and series fields.
- A Windows Browse workspace using WebView2 with the same cross-platform models.

## FAQ

### Do readers need to install Calibre?

No. Release builds bundle Calibre, so readers can convert supported files after installing MobiVerse.

### Does MobiVerse remove DRM?

No. MobiVerse only converts DRM-free or otherwise readable files. Protected files are reported as conversion failures.

### Why does macOS say Apple cannot verify the app?

The current public DMG is not Apple Developer ID notarized yet. A notarized build is on the release roadmap.

### Where are converted EPUB files saved?

MobiVerse writes EPUBs next to the original source file and avoids overwriting existing files.

### Is my book uploaded anywhere?

No. Conversion runs locally on your computer.

## Privacy

MobiVerse runs locally on your computer. Your books are not uploaded to a server by this app.

## Development

### Requirements

- macOS 14 or later
- Swift 6 / Xcode 26 or later
- A local Calibre app only on the build machine, used as the source copied into distributable app bundles. Defaults to `/Applications/calibre.app`; override with `CALIBRE_APP=/path/to/calibre.app`.
- EPUBCheck and OpenJDK, required for every packaged validation or release build. The script detects common Homebrew locations or accepts `EPUBCHECK_JAR=/path/to/epubcheck.jar` and `EPUBCHECK_JAVA_HOME=/path/to/java/home`.

### Run from source

```sh
swift run Mobi2EpubTransfer
```

Development runs use bundled Calibre when launched from an app bundle created by `scripts/package-app.sh`. Otherwise, they fall back to a system Calibre installation.

### Package app

```sh
scripts/package-app.sh
```

The generated app is written to:

```text
.build/MobiVerse.app
```

### Package DMG

```sh
scripts/package-dmg.sh
```

The generated installer image is written to:

```text
.build/MobiVerse-2.4.1.dmg
```

Development builds use ad-hoc signing by default. They are suitable for local testing, but macOS Gatekeeper will block them after download from the internet.

### Package a notarized release

Public macOS distribution requires an Apple Developer Program account, a `Developer ID Application` certificate in Keychain, and Apple notarization credentials.

Store notarization credentials once:

```sh
xcrun notarytool store-credentials mobiverse-notary \
  --apple-id "you@example.com" \
  --team-id "TEAMID" \
  --password "app-specific-password"
```

Then build the release DMG:

```sh
SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" \
BUNDLE_IDENTIFIER="com.yourcompany.mobiverse" \
NOTARIZE=1 \
NOTARYTOOL_PROFILE="mobiverse-notary" \
scripts/package-dmg.sh
```

The script signs the app with hardened runtime and timestamp, signs the DMG, submits it to Apple notarization, staples the ticket, and validates the final DMG.

### EPUBCheck requirement

```sh
EPUBCHECK_JAR=/path/to/epubcheck.jar scripts/package-dmg.sh
```

Both scripts bundle Calibre, EPUBCheck, and its Java runtime. They fail instead of producing an incomplete or non-runnable package when any dependency is unavailable.

## Test

```sh
swift test
```

## License

MobiVerse is licensed under GPLv3 or later.

If you distribute an app bundle that includes Calibre, also satisfy Calibre's GPLv3 source-code distribution requirements for the bundled Calibre version. See [ThirdPartyNotices.md](ThirdPartyNotices.md).
