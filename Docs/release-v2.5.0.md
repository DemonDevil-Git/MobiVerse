# MobiVerse 2.5.0 (15)

MobiVerse 2.5.0 makes reading more immersive, makes browser downloads easier to manage, and strengthens first-launch verification for newly installed copies.

## Highlights

- Rebuilt the EPUB reader around distraction-free reading with auto-hiding controls and cursor, full-screen support, and quick keyboard navigation.
- Added single-page, two-page spread, and continuous-scroll comic modes with direction-aware page ordering for left-to-right and right-to-left books.
- Added adaptive comic canvas colors, image caching, adjacent-page preloading, and smoother page transitions.
- Improved the text reader with reading-direction-aware navigation while preserving theme, typography, and reading-position controls.
- Reworked Browse downloads into a smoothly scrolling vertical list with clearer progress and status information.
- Added per-download record removal with confirmation. Removing a completed record never deletes the downloaded book file; removing an active record cancels the transfer and removes its partial file.

## First-launch reliability

- The packaged app still launches against a fresh preferences directory and must remain alive through the stability window.
- The final DMG now passes integrity verification, copies MobiVerse into a clean Applications-like directory, verifies the copied app's deep strict signature, detaches the installer image, and cold-launches the installed copy with fresh preferences.
- This preserves the packaged-resource fix introduced in 2.4.1 and catches regressions that only appear after copying the app out of its DMG.

## Verification

- 51 macOS automated tests passed across 14 suites.
- 55 Windows core tests passed.
- Shell packaging scripts and website JavaScript passed syntax checks.
- The packaged app and the cleanly installed DMG copy passed fresh-user launch stability checks.
- App version: `2.5.0 (15)`.
- Architecture: Apple Silicon (`arm64`).
- Minimum system: macOS 14.
- DMG SHA-256: `adb568eab5a90aeedf5fb04419696df25feafbf3cb774d9ecf2169292caeb19e`.

## Installation

1. Download `MobiVerse-2.5.0.dmg` from this release.
2. Open the DMG and drag `MobiVerse.app` to Applications.
3. Replace the previous version when Finder asks.

## Distribution note

This build is ad-hoc signed because no Apple Developer ID identity is available in the release environment. It is not Apple-notarized, so macOS may require the user to approve opening it. That Gatekeeper prompt is separate from an application first-launch crash. A future public build requires a Developer ID Application certificate and notarization to eliminate the warning.
