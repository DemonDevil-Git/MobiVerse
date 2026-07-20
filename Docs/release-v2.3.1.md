# MobiVerse 2.3.1 (12)

MobiVerse 2.3.1 is a macOS reliability release for browser downloads and comic conversion.

## Fixes

- Prevented a SwiftUI import-review binding race from crashing the app while the review sheet closes.
- Corrected fixed-layout comic OPF output so EPUBCheck receives exactly one `dcterms:modified` value, SVG declarations on XHTML manifest items, and no invalid SVG property on spine item references.
- Made main-frame PDF responses in Browse download automatically, including temporary signed URLs without a `.pdf` suffix.
- Kept embedded PDF frames viewable and added a persistent setting for automatic PDF download versus browser preview.

## Verification

- 49 automated tests passed across 14 suites.
- The release app bundles Calibre, EPUBCheck, and Java.
- DMG SHA-256: `28d4a01cdbc775da8cc2ff7764f01f448404a2771fbdbb0b5a7df1040c69b45b`.
- Apple Silicon (`arm64`), macOS 14 or later.

## Distribution note

This build is ad-hoc signed and is not Apple-notarized. macOS may require the user to confirm opening an app downloaded from the internet.
