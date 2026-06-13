# MobiVerse v1.0.0

MobiVerse is a native macOS converter for turning Kindle books, comic archives, and PDF comics into polished EPUB files for Apple Books and modern EPUB readers.

## Who Should Download

- macOS readers who want to convert MOBI, AZW, AZW3, CBZ, CBR, ZIP, or PDF sources into EPUB.
- Manga and illustrated-book readers who care about stable image sizing, clean covers, and Apple Books-friendly page layout.
- Users who want a local desktop workflow without uploading books to a cloud service.

## What's Included

- Native macOS SwiftUI app.
- Bundled Calibre for local conversion. Readers do not need to install Calibre separately.
- Fixed-layout comic EPUB post-processing for stable Apple Books reading.
- EPUB preview with horizontal page swiping, fullscreen viewing, zoom controls, and text EPUB fallback preview.
- Batch conversion history with reveal, report, retry, and missing-output status.
- Support for MOBI, AZW, AZW3, CBZ, CBR, ZIP, and PDF inputs.

## Known Limitations

- MobiVerse does not remove DRM and will report protected or unreadable files as conversion failures.
- The current v1.0.0 DMG is not Apple Developer ID notarized. macOS Gatekeeper may show an "Apple could not verify MobiVerse" warning after download.
- EPUBCheck is optional; validation is skipped unless an EPUBCheck runtime is bundled or available.
- Extremely large PDF or archive conversions can take time because conversion and EPUB rebuilding happen locally.

## Install

1. Download `MobiVerse-1.0.0.dmg` from this release.
2. Open the DMG.
3. Drag `MobiVerse.app` into `Applications`.
4. Launch MobiVerse and drop supported files into the window.

## Signing and Notarization

- App conversion runtime: Calibre is bundled in the release app.
- DMG signing status: not Developer ID signed.
- Apple notarization status: not notarized.
- A signed and notarized public DMG is planned for the next distribution build.

## SHA256

```text
d2c91142e72f94c27c9971f4f1afc787493a52311f7bd8029eec5af03aa606b8  MobiVerse-1.0.0.dmg
```
