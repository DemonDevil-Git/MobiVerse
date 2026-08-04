# MobiVerse 2.4.0 (13)

MobiVerse 2.4.0 is a macOS usability and localization release focused on a responsive 3D shelf, reliable Browse downloads, and a complete Simplified Chinese interface.

## Highlights

- Added complete Simplified Chinese localization with an in-app selector for Simplified Chinese, English, or the macOS system language.
- Added an interactive 3D shelf with direct visible-book selection and smooth spring transitions.
- Stabilized 3D shelf hit testing by locking the mouse-down target and keeping hover effects from changing book geometry.
- Prewarmed and retained book nodes so random selections remain responsive without sacrificing transition animation.
- Moved converting, validating, and newly completed books to the front of the shelf.
- Added animated Browse download activity and made Cancel stop and remove active downloads immediately.
- Optimized cover and metadata extraction for large EPUB files without expanding the full archive.
- Removed the redundant green completion strip from 3D book covers.

## Verification

- 51 automated tests passed across 14 suites.
- Simplified Chinese was verified in the Shelf, Browse, browser settings, and 3D shelf interfaces.
- The release app bundles Calibre, EPUBCheck, and Java.
- DMG SHA-256: `b1a901de4ce92dc60cb598eb9c6ae224e2d1c75b0e318742984346bd163669fd`.
- Apple Silicon (`arm64`), macOS 14 or later.

## Installation

1. Download `MobiVerse-2.4.0.dmg` from this release.
2. Open the DMG and drag `MobiVerse.app` to `Applications`.
3. Replace the previous version when Finder asks.

## Distribution note

This build is ad-hoc signed and is not Apple-notarized. macOS may require the user to confirm opening an app downloaded from the internet.
