# MobiVerse 2.3.1 (12)

MobiVerse 2.3.1 is a reliability release for browser downloads and comic conversion, with macOS and Windows 11 ARM64 packages at the same version, build number, and user-facing feature level.

## Fixes

- Prevented a SwiftUI import-review binding race from crashing the app while the review sheet closes.
- Corrected fixed-layout comic OPF output so EPUBCheck receives exactly one `dcterms:modified` value, SVG declarations on XHTML manifest items, and no invalid SVG property on spine item references.
- Made main-frame PDF responses in Browse download automatically, including temporary signed URLs without a `.pdf` suffix.
- Kept embedded PDF frames viewable and added a persistent setting for automatic PDF download versus browser preview.

## Windows feature synchronization

- Added Shelf and Browse workspaces, application appearance preferences, browser tabs, bookmarks, downloads, download-directory settings, and privacy clearing.
- Added local book classification and import review with selectable text/comic layouts and comic reading direction.
- Added EPUB 3 text conversion with ruby preservation and structural repair for invalid identifiers, broken local resources, and NCX navigation order.
- Added direction-aware fixed-layout EPUB output and the 2.3.1 OPF metadata/SVG corrections.
- Rebuilt text preview as a section-aware paginated reader with Paper, Sepia, and Night themes, text-size and line-spacing controls, and section/page restoration.
- Added automatic main-page PDF downloads, including signed URLs without `.pdf`, while leaving embedded PDFs viewable.

## Verification

- 49 automated tests passed across 14 suites.
- The release app bundles Calibre, EPUBCheck, and Java.
- DMG SHA-256: `28d4a01cdbc775da8cc2ff7764f01f448404a2771fbdbb0b5a7df1040c69b45b`.
- Apple Silicon (`arm64`), macOS 14 or later.
- Windows package version: `2.3.1.12` for Windows 11 ARM64 (x64 application compatibility with native ARM64 WebView2).
- Windows core tests: 55 passed; the Windows application code compiled on macOS with 0 errors and 0 warnings.
- Windows installer archive: 1,836 files verified by 7-Zip; embedded application and loose XAML hashes verified after extraction.
- Windows installer SHA-256: `b593efa9cc12af448035b2f0ddd83a129c0d479eb82953bcaa02b7192b78fef1`.
- Final Windows runtime behavior still requires the manual Windows checklist included with the installer.
- The feature-by-feature implementation and validation status is recorded in `Docs/windows-parity-v2.3.1.md`.

## Distribution note

The macOS build is ad-hoc signed and is not Apple-notarized. macOS may require the user to confirm opening an app downloaded from the internet. The Windows package is unsigned and may trigger a Microsoft Defender SmartScreen warning.
