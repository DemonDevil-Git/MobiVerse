# MobiVerse

**Convert Kindle books, comic archives, and PDF comics into polished EPUBs for Apple Books and modern EPUB readers.**

MobiVerse is a native macOS app built for illustrated reading. It converts MOBI, AZW, AZW3, CBZ, CBR, ZIP, and PDF source files into EPUB, then rebuilds comic-style output as clean fixed-layout pages so manga and image-heavy books feel stable, centered, and smooth.

[Download MobiVerse for macOS](https://github.com/DemonDevil-Git/MobiVerse/releases/latest/download/MobiVerse-1.0.0.dmg)

## Why MobiVerse

- **Made for comics and illustrated books**  
  Image pages are rebuilt into clean fixed-layout EPUB3 pages with stable sizing, no unexpected margins, and right-to-left manga metadata.

- **Works without asking readers to install Calibre**  
  The distributable app can bundle Calibre so conversion works immediately after installation.

- **Apple Books friendly**  
  MobiVerse writes cover metadata, fixed-layout display options, and self-contained image pages to avoid stretched or black pages.

- **Built-in EPUB preview**  
  Open converted EPUBs directly in the app, flip through image pages with native horizontal paging, zoom in, and use fullscreen preview.

- **Batch conversion with history**  
  Drag in multiple books, track progress, reveal outputs, open reports, and keep conversion history across launches.

## Supported Inputs

| Format | Use case |
| --- | --- |
| MOBI, AZW, AZW3 | Kindle-style ebooks without DRM |
| CBZ, ZIP | Comic archives made from ordered image files |
| CBR | RAR-based comic archives readable by Calibre |
| PDF | PDF comics and image-heavy documents |

MobiVerse does not remove DRM. Protected or unreadable files are reported clearly.

## Install

1. Download the latest DMG from [Releases](https://github.com/DemonDevil-Git/MobiVerse/releases).
2. Open `MobiVerse-1.0.0.dmg`.
3. Drag `MobiVerse.app` into `Applications`.
4. Launch MobiVerse and drop supported files into the window.

Converted EPUB files are written next to the original source file without overwriting existing EPUBs.

## Preview

The built-in preview focuses on comic/image-page EPUBs:

- native horizontal page swiping
- fullscreen preview
- zoom in, zoom out, and fit controls
- current-page recentering after fullscreen/window size changes

Text EPUBs fall back to a simple WebView preview.

## Privacy

MobiVerse runs locally on your Mac. Your books are not uploaded to a server by this app.

## Development

### Requirements

- macOS 14 or later
- Swift 6 / Xcode 26 or later
- Calibre installed at `/Applications/calibre.app` when building a distributable app
- Optional: `epubcheck` in `PATH` or `EPUBCHECK_JAR=/path/to/epubcheck.jar`

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
.build/MobiVerse-1.0.0.dmg
```

### Bundle EPUBCheck

```sh
EPUBCHECK_JAR=/path/to/epubcheck.jar scripts/package-dmg.sh
```

## Test

```sh
swift test
```

## License

MobiVerse is licensed under GPLv3 or later.

If you distribute an app bundle that includes Calibre, also satisfy Calibre's GPLv3 source-code distribution requirements for the bundled Calibre version. See [ThirdPartyNotices.md](ThirdPartyNotices.md).
