# MobiVerse v2.0.0

MobiVerse 2.0 is a polished macOS reader-converter release focused on a better visual library workflow for EPUB, Kindle-style ebooks, comic archives, and PDF comics.

## What's New

- Warm bookshelf-style macOS interface with a visual reading-desk drop zone.
- Sidebar conversion summary for total conversions, succeeded, failed, and in-progress jobs.
- Converted EPUB cards now show extracted cover thumbnails instead of generic placeholders.
- Cover thumbnails are cached locally so completed shelves restore quickly after reopening the app.
- Grid and list shelf layouts are available from the shelf toolbar.
- Completed-book cards show title, completion time, status, actions, and progress without displaying full local file paths.
- App resources are bundled into packaged builds, including the new hero artwork and sidebar still-life artwork.

## Conversion and Reading

- Opens EPUB files directly in the built-in preview.
- Converts DRM-free MOBI, AZW, AZW3, CBZ, CBR, ZIP, and PDF files into EPUB.
- Rebuilds comic/image-heavy EPUBs into fixed-layout EPUB3 output for more stable Apple Books reading.
- Keeps conversion local on your Mac.
- Writes converted EPUBs next to the original source file without overwriting existing files.

## Known Limitations

- MobiVerse does not remove DRM and reports protected or unreadable files as conversion failures.
- This DMG is not Apple Developer ID notarized. macOS Gatekeeper may show an "Apple could not verify MobiVerse" warning after download.
- EPUBCheck is optional; validation is skipped unless an EPUBCheck runtime is bundled or available.
- Very large PDF or archive conversions can take time because conversion and EPUB rebuilding happen locally.

## Install

1. Download `MobiVerse-2.0.0.dmg` from this release.
2. Open the DMG.
3. Drag `MobiVerse.app` into `Applications`.
4. Launch MobiVerse and drop supported files into the window.

## Signing and Notarization

- App conversion runtime: Calibre is bundled when the release is built with the default packaging flow.
- DMG signing status: not Developer ID signed unless a signing identity is supplied during packaging.
- Apple notarization status: not notarized unless `NOTARIZE=1` is supplied during packaging.

## SHA256

```text
cf6646f75fba1bb871e4cfa19fc8113a6629c2ba89b9248387eb2a9204dda32e  MobiVerse-2.0.0.dmg
```
