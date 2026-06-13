# MobiVerse

MobiVerse is a native macOS SwiftUI app for converting MOBI, AZW, AZW3, CBZ, CBR, ZIP, and PDF books into EPUB files. The first version prioritizes illustrated books and comics by keeping the workflow conservative: Calibre performs the conversion, EPUBCheck validates the result, and output files are written next to the original book without overwriting existing EPUBs.

## Requirements

- macOS 14 or later
- Swift 6 / Xcode 26 or later for development
- Calibre installed at `/Applications/calibre.app` when building a distributable app
- Optional: `epubcheck` in `PATH` for structural validation reports

## Run

```sh
swift run Mobi2EpubTransfer
```

Development runs use bundled Calibre when launched from an app bundle created by `scripts/package-app.sh`. Otherwise, they fall back to a system Calibre installation.

## Package App With Calibre

Install Calibre in `/Applications/calibre.app`, then run:

```sh
scripts/package-app.sh
```

To bundle EPUBCheck as well, provide its jar:

```sh
EPUBCHECK_JAR=/path/to/epubcheck.jar scripts/package-app.sh
```

The script builds a release binary and assembles:

```text
.build/MobiVerse.app
```

The generated app contains:

- `Contents/MacOS/Mobi2EpubTransfer`
- `Contents/Resources/ThirdParty/calibre.app`
- Optional: `Contents/Resources/ThirdParty/epubcheck/epubcheck.jar`
- `Contents/Resources/ThirdPartyNotices.md`

## Test

```sh
swift test
```

## License

MobiVerse is licensed under GPLv3 or later. If you distribute an app bundle that
includes Calibre, also satisfy Calibre's GPLv3 source-code distribution
requirements for the bundled Calibre version.

## Current Scope

- Drag or choose `.mobi`, `.azw`, `.azw3`, `.cbz`, `.cbr`, `.zip`, and `.pdf` files.
- Convert each file with Calibre into a same-folder `.epub` output.
- Treat `.zip` comic archives as `.cbz` during conversion so Calibre reads them as comics.
- Prefer bundled Calibre, with system Calibre as a development fallback.
- Optimize comic EPUB output after conversion by removing fixed image sizing, removing page margins, adding right-to-left manga metadata, and generating page-range TOC entries.
- Classify common conversion failures, including likely DRM-protected files.
- Generate a conversion report with EPUBCheck output when available.
- Mark conversions as succeeded, succeeded with warnings, or failed.

The app does not remove DRM.

## Third-Party Licensing

Calibre is GPLv3 software. If you distribute an app bundle that includes Calibre, distribute the matching Calibre source code or provide a written/source offer that satisfies GPLv3. The package script copies a notice file into the app resources, but release compliance is still the distributor's responsibility.
