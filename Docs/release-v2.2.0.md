# MobiVerse v2.2.0

MobiVerse 2.2 expands the local reader-converter to Windows and hardens EPUB preview handling on macOS.

## Downloads

- `MobiVerse-2.2.0.dmg` — macOS 14 or later, with bundled Calibre.
- `MobiVerse-2.2.0-Windows11-ARM64-Setup.exe` — Windows 11 ARM64 installer using x64 application compatibility and native ARM64 WebView2.

## Highlights

- Added the Windows desktop application, offline installer workflow, and Windows CI.
- Confined EPUB package, page, and image references to the extracted book directory.
- Disabled book-provided JavaScript in text EPUB previews.
- Blocked remote web resources and navigation outside the extracted EPUB.
- Switched EPUB WebView data to non-persistent storage.

MobiVerse performs conversion locally and does not remove DRM.

## SHA-256

```text
10d25873bbc8c7b1eabe7bdabd8c53e0bf441cac1e2911b20b4dc1df3b7b86cd  MobiVerse-2.2.0.dmg
360feede3f56086f96aa3c3175f06bfdfda75acd6d0b9c11f1960b134e177130  MobiVerse-2.2.0-Windows11-ARM64-Setup.exe
```
