# MobiVerse 2.4.1 (14)

MobiVerse 2.4.1 is a macOS reliability patch focused on safe first launch for newly installed users and precise workspace toolbar alignment.

## Fixes

- Fixed a first-launch crash caused by resolving localized resources through a development-only SwiftPM bundle accessor after installation.
- Kept the Browse new-tab button in the trailing action area immediately left of Downloads.
- Centered the Shelf/Browse workspace control for short Simplified Chinese labels.
- Strengthened release smoke testing so the packaged app must launch with a fresh preferences directory and remain alive through a stability window.
- Added a second launch check from the final mounted DMG and reliable cleanup of the test mount.

## Verification

- 51 automated tests passed across 14 suites.
- Shell packaging scripts and website JavaScript passed syntax checks.
- The packaged app and the app inside the mounted DMG each launched with a fresh preferences directory and remained running for the full five-second stability window.
- The DMG passed `hdiutil verify`.
- The app passed deep strict code-signature verification.
- App version: `2.4.1 (14)`.
- Architecture: Apple Silicon (`arm64`).
- Minimum system: macOS 14.
- DMG SHA-256: `7e34563f413cd6a6e3cb2ced9c950bead34e2e48c772bf9cdfc57c632ca1c517`.

## Installation

1. Download `MobiVerse-2.4.1.dmg` from this release.
2. Open the DMG and drag `MobiVerse.app` to Applications.
3. Replace the previous version when Finder asks.

## Distribution note

This build is ad-hoc signed because no Apple Developer ID identity is available in the release environment. It is not Apple-notarized, so macOS may require the user to approve opening it. This Gatekeeper prompt is separate from the application first-launch crash fixed in this release.
