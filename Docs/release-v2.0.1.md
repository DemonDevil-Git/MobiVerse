# MobiVerse v2.0.1

MobiVerse 2.0.1 is a startup reliability hotfix for the 2.0 visual library release.

## Fixed

- Fixes an immediate launch crash on Macs that did not contain the developer build directory.
- Packages the SwiftPM image resource bundle inside `MobiVerse.app/Contents/Resources`.
- Loads app artwork from the installed app bundle without depending on SwiftPM's development-only fallback path.
- Fails the packaging process if required visual resources are missing, preventing another incomplete DMG release.

## Included Features

- Opens EPUB files directly in the built-in preview.
- Converts DRM-free MOBI, AZW, AZW3, CBZ, CBR, ZIP, and PDF files into EPUB.
- Shows extracted EPUB covers in the visual conversion shelf.
- Rebuilds image-heavy EPUBs into fixed-layout EPUB3 output for Apple Books.
- Bundles Calibre so readers do not need to install it separately.

## Install

1. Remove the affected MobiVerse 2.0.0 app from `Applications`.
2. Download `MobiVerse-2.0.1.dmg` from this release.
3. Drag `MobiVerse.app` into `Applications`.
4. Launch MobiVerse normally.

## Known Limitations

- MobiVerse does not remove DRM.
- This DMG is not Apple Developer ID notarized. macOS Gatekeeper may require users to approve opening it manually.
- EPUBCheck validation is skipped unless an EPUBCheck runtime is available.

## Verification

- App version: `2.0.1 (4)`
- Architecture: Apple Silicon (`arm64`)
- The packaged app passed strict recursive code-signature validation.
- The packaged app remained running after launch with no resource assertion or fatal log entries.

## SHA256

```text
d2cc9a1d4e5d2965a3732596fe0f3caa383dc4529bccc68c62537ede49cc162e  MobiVerse-2.0.1.dmg
```
