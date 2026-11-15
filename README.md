# Qeniro PDF

A full-featured native PDF app for **macOS 14+** and **iPhone (iOS 17+)**, built with Swift, SwiftUI, PDFKit, Vision and PDFium.
The user interface is in Turkish and supports light and dark mode. Turkish documentation: [README.tr.md](README.tr.md).

## Features

| Area | What it does |
|---|---|
| Viewer | Open, navigate, zoom, rotate, hand/select tools, search, print, save, thumbnails, password-protected PDFs, undo/redo |
| Layout | Acrobat-style tabs (All tools · Edit · Convert · E-sign), left tool panel, floating quick-tool rail |
| Real text editing | Click existing text to change it in the PDF content stream (PDFium), add new real text objects |
| Edit | Images, links, header/footer with page numbers, watermark, crop, rotate, delete, extract and reorder pages |
| Annotations | Sticky notes, highlight, underline/strikeout, freehand ink, rectangles and ellipses |
| Fill & sign | Draw / type / image signatures, initials, text, checkboxes, radio buttons, dates, flatten on apply |
| Forms | Create text fields, checkboxes, radio buttons, dropdowns and signature fields |
| Certificate signing (macOS) | PAdES signatures (adbe.pkcs7.detached, SHA-256) with a Keychain identity; signature verification |
| Organize | Merge, split, compress, password protection, redaction, remove sensitive data |
| Create | From images, Word/RTF/ODT/HTML/text, blank pages, clipboard; optional LibreOffice bridge for Excel/PowerPoint/iWork |
| OCR | Searchable PDFs with Apple Vision; recognition language selectable (Turkish by default) |
| Convert | DOCX, XLSX, PPTX (pure-Swift OpenXML writer), JPEG/PNG/TIFF, RTF/TXT/HTML |
| iPhone | Document camera scanning, PencilKit signatures, Files app integration ("Open in Qeniro PDF") |

## Building — macOS

Requirements: Xcode 16+, [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`), and an internet
connection on the first build (PDFium is downloaded into `Vendor/pdfium`).

```bash
./build.sh run        # build (Debug) and launch
./build.sh release    # Release build
./build.sh test       # unit tests
./make_dmg.sh         # Release build packaged as "Qeniro PDF <version>.dmg"
```

Double-clickable shortcuts in the project root: `Derle ve Calistir.command` (build & run), `DMG Olustur.command`
(create DMG), `Fazla Kopyalari Temizle.command` (remove leftover build copies from Launchpad).

The app is ad-hoc signed. If macOS warns on first launch, right-click the app in Applications and choose **Open**.

## Building — iPhone

Requirements: Xcode 16+ with the iOS platform installed (Xcode › Settings › Components › iOS), XcodeGen.

```bash
./iOS/build-ios.sh            # Simulator build (unsigned)
./iOS/build-ios.sh run        # build, boot a simulator, install and launch
DEVELOPMENT_TEAM=XXXXXXXXXX ./iOS/build-ios.sh device   # signed build installed on a connected iPhone
```

`iPhone'a Kur.command` detects the signed-in Xcode team automatically, then builds and installs on the
cable-connected iPhone. The device needs Developer Mode enabled, and Xcode must be signed in to the developer Apple ID
(Xcode › Settings › Accounts).

## Architecture

- **XcodeGen** — `project.yml` and `iOS/project.yml` generate the Xcode projects; `.xcodeproj` files are not committed.
- **PDFium** — prebuilt binaries from [bblanchon/pdfium-binaries](https://github.com/bblanchon/pdfium-binaries)
  (`chromium/8057`). macOS embeds `libpdfium.dylib`; iOS wraps device and simulator builds into `pdfium.xcframework`.
  Exposed to Swift through a bridging header; see `Services/PDFiumEditor.swift`.
- **Rendering stays in PDFKit** — after each PDFium edit the document is reloaded into PDFKit, keeping page and zoom,
  and the previous version goes on the undo stack.
- **Shared code** — platform-independent services (`ZipWriter`, `OfficeExportService`, `PDFOCRService`, `Formatters`)
  are compiled into both apps; UIKit counterparts of AppKit-dependent services live in `iOS/QeniroPDFiOS/Services/`.
- **No sandbox on macOS** — needed to list iCloud Drive / CloudStorage folders and run the optional LibreOffice bridge.

```
project.yml, build.sh, make_dmg.sh, Config/
QeniroPDF/         macOS app: App, Models, PDFium, Services, Views, Theme, Resources
QeniroPDFTests/    service unit tests
iOS/               iPhone app: project.yml, build-ios.sh, QeniroPDFiOS/
preview/           HTML design preview
Vendor/            downloaded by the build scripts (not committed)
```

## Known limitations

- **Subset fonts** — if new characters are missing from a PDF's embedded subset font, that line is re-set in the
  closest system font (same position, size and colour); file size grows by the embedded font.
- **Line-level editing** — paragraphs do not reflow; text inside Form XObjects cannot be edited.
- **Scanned pages** have no editable text; OCR adds an invisible searchable layer only.
- **Office conversion** keeps text, formatting, tables and images but not a 100% identical layout.
- **Certificate signing** needs a Keychain identity with a private key; editing a signed PDF invalidates its signatures.
- Not supported: PDF/A output, App Store distribution / notarization. Certificate signing and creating PDFs from
  .docx are macOS-only.

## Licenses

PDFium is licensed under BSD 3-Clause and Apache 2.0 (© The PDFium Authors); the prebuilt binaries come from
bblanchon/pdfium-binaries (MIT). Third-party licence texts are downloaded with the binaries into `Vendor/pdfium/licenses/`
and must be shipped with any distributed build.
