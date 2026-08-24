# Windows parity audit — MobiVerse 2.3.1 (Build 12)

This audit tracks user-facing parity with the macOS 2.3.1 release. “Implemented” means the Windows source and package contain the feature. Windows runtime behavior remains subject to the included manual checklist.

| macOS 2.3.1 capability | Windows implementation | Automated evidence | Windows manual check |
|---|---|---|---|
| Shelf / Browse workspaces | WPF shelf plus embedded WebView2 workspace | App compile passed | Required |
| Browser tabs and navigation | Per-tab WebView2 instances with back/forward/reload/home/search | App compile passed | Required |
| Browser bookmarks | Persistent local bookmark store | App compile passed | Required |
| Download list and folder | Progress, pause/resume/cancel/reveal, persistent directory | Download policy and file-validation tests | Required |
| Main-page PDF auto-download | Response MIME detection, signed-URL support, persistent toggle | Browser policy tests | Required |
| Embedded PDF preview | Auto-download policy restricted to main-page responses | Browser policy tests | Required |
| Browser privacy | WebView2 profile data clearing | App compile passed | Required |
| Local import review | Persistent pending imports, confidence/evidence, manual override | Classifier tests | Required |
| Text/comic classification | Archive, EPUB, PDF, MOBI/AZW/AZW3 classification paths | Classifier tests | Required with representative books |
| Direct EPUB shelf import | EPUB is added without reconversion and opens in the reader | Preview-parser tests | Required |
| EPUB 3 text conversion | Calibre EPUB 3 profile | Converter compile and core tests | Required |
| Ruby/semantic preservation | Text repair avoids rewriting semantic markup | Ruby-preservation test | Required with Japanese EPUB |
| Text EPUB structural repair | Invalid IDs, broken local resources, NCX playOrder | Text post-processor tests | Required |
| Comic fixed layout | Direction-aware EPUB 3 package generation | Archive metadata tests | Required |
| 2.3.1 comic OPF fix | One modified value, SVG on manifest XHTML only | Comic metadata tests | Required via EPUBCheck report |
| Native scan-PDF conversion | Windows.Data.Pdf page renderer | App compile passed | Required |
| Paginated text reader | All spine sections, page navigation, progress | Preview parser and position tests | Required |
| Reader appearance | Paper/Sepia/Night, text size, line spacing | App compile passed | Required |
| Reading-position restoration | Section + page schema with legacy migration | Position-store tests | Required |
| Comic reader | Paging, slider, zoom, fit, keyboard, wheel, full screen | App compile passed | Required |
| Application appearance | System/Light/Dark persistent setting | App compile passed | Required |

Verification summary:

- 55 Windows core tests passed.
- Windows application C# compiled against WindowsDesktop, WebView2, and Windows SDK APIs with 0 errors and 0 warnings.
- Five XAML files passed XML validation.
- The self-extracting installer archive passed 7-Zip integrity testing: 1,836 files, 105 folders.
- Installer SHA-256: `b593efa9cc12af448035b2f0ddd83a129c0d479eb82953bcaa02b7192b78fef1`.
