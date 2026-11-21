import Foundation
import UIKit
import PDFKit
import ImageIO
import UniformTypeIdentifiers

// macOS'taki QeniroPDF/Services/PDFOrganizeServices.swift ve PDFCreateService.swift
// dosyalarının iOS karşılıkları. Quartz filtresi (macOS'a özgü) yerine PDFKit'in
// iOS 16.4+ yazma seçenekleri ve görüntüye çevirme kullanılır.

// MARK: - Birleştir

enum PDFMergeService {
    /// PDF dosyalarını verilen sırayla birleştirir.
    static func merge(_ urls: [URL], to output: URL) throws -> Int {
        guard !urls.isEmpty else { throw QPDFError.noPages }
        let out = PDFDocument()
        for url in urls {
            let doc = try SecurityScope.access(url) { try DocTools.open(url) }
            for i in 0..<doc.pageCount {
                if let p = doc.page(at: i)?.copy() as? PDFPage { out.insert(p, at: out.pageCount) }
            }
        }
        guard out.pageCount > 0 else { throw QPDFError.noPages }
        try DocTools.write(out, to: output)
        return out.pageCount
    }
}

// MARK: - Böl

enum SplitMode: Hashable, Sendable {
    case ranges(String)
    case everyN(Int)
    case single
}

enum PDFSplitService {
    static func split(data: Data, mode: SplitMode, folder: URL, baseName: String) throws -> [URL] {
        let doc = try DocTools.open(data: data, name: baseName)
        let n = doc.pageCount
        guard n > 0 else { throw QPDFError.noPages }
        var groups: [[Int]] = []
        switch mode {
        case .ranges(let text):
            groups = DocTools.parseRanges(text, pageCount: n)
            if groups.isEmpty { throw QPDFError.message(String(localized: "Sayfa aralığı anlaşılamadı. Örnek: 1-3, 5, 8-")) }
        case .everyN(let k):
            let step = max(1, k)
            var i = 0
            while i < n { groups.append(Array(i..<min(i + step, n))); i += step }
        case .single:
            groups = (0..<n).map { [$0] }
        }
        var urls: [URL] = []
        for (k, g) in groups.enumerated() {
            let part = DocTools.rebuiltCopy(of: doc, pages: g)
            let label: String
            if g.count == 1 { label = "s\(g[0] + 1)" } else { label = "s\(g[0] + 1)-\(g[g.count - 1] + 1)" }
            let url = folder.appendingPathComponent("\(baseName)_\(k + 1)_\(label).pdf")
            try DocTools.write(part, to: url)
            urls.append(url)
        }
        return urls
    }
}

// MARK: - Sıkıştır

enum CompressionLevel: String, CaseIterable, Identifiable, Sendable {
    case low, medium, high
    var id: String { rawValue }
    var title: String {
        switch self {
        case .low: return String(localized: "Düşük (en iyi kalite)")
        case .medium: return String(localized: "Orta (önerilen)")
        case .high: return String(localized: "Yüksek (en küçük boyut)")
        }
    }
    var quality: Double { self == .low ? 0.75 : (self == .medium ? 0.55 : 0.35) }
    var dpi: CGFloat { self == .low ? 150 : (self == .medium ? 110 : 80) }
}

struct CompressResult: Sendable {
    var before: Int64
    var after: Int64
    var output: URL
    var note: String?
}

enum PDFCompressService {
    static func compress(data: Data, name: String, output: URL, level: CompressionLevel, rasterize: Bool) throws -> CompressResult {
        let before = Int64(data.count)
        let doc = try DocTools.open(data: data, name: name)
        var note: String?
        if rasterize {
            try rasterizeAll(doc: doc, level: level, output: output)
            note = String(localized: "Sayfalar görüntüye çevrildi; metin seçilebilirliği OCR ile geri eklendi.")
        } else {
            // iOS 16.4+: görselleri JPEG olarak yeniden kaydet ve ekran çözünürlüğüne indir.
            var opts: [PDFDocumentWriteOption: Any] = [.saveImagesAsJPEGOption: true]
            if level != .low { opts[.optimizeImagesForScreenOption] = true }
            if !doc.write(to: output, withOptions: opts) {
                try DocTools.write(doc, to: output)
            }
        }
        let after = Fmt.fileSize(of: output)
        if after >= before && !rasterize {
            note = String(localized: "Bu dosya zaten iyi sıkıştırılmış; boyut azaltılamadı. Daha fazla küçültmek için \"Sayfaları görüntüye çevir\" seçeneğini deneyin.")
            // Daha büyük çıktı yerine özgün veriyi ver.
            try data.write(to: output, options: .atomic)
        }
        return CompressResult(before: before, after: Fmt.fileSize(of: output), output: output, note: note)
    }

    private static func rasterizeAll(doc: PDFDocument, level: CompressionLevel, output: URL) throws {
        let out = PDFDocument()
        for i in 0..<doc.pageCount {
            guard let page = doc.page(at: i) else { continue }
            autoreleasepool {
                guard let cg = PageRenderer.renderImage(page: page, dpi: level.dpi) else { return }
                guard let jpeg = UIImage(cgImage: cg).jpegData(compressionQuality: level.quality),
                      let src = CGImageSourceCreateWithData(jpeg as CFData, nil),
                      let jpgImage = CGImageSourceCreateImageAtIndex(src, 0, nil) else { return }
                let lines = (try? PDFOCRService.recognize(cgImage: cg, pageSize: page.bounds(for: .mediaBox).size)) ?? []
                let keep = page.annotations.filter { $0.isLink }
                if let np = PageRenderer.rebuild(page: page, contentImage: jpgImage, keep: keep, extra: { ctx in
                    PageRenderer.drawInvisibleText(lines, in: ctx)
                }) {
                    out.insert(np, at: out.pageCount)
                }
            }
        }
        guard out.pageCount > 0 else { throw QPDFError.noPages }
        try DocTools.write(out, to: output)
    }
}

// MARK: - Koruma

struct ProtectOptions: Sendable {
    var openPassword: String
    var permissionsPassword: String
    var allowPrinting: Bool
    var allowCopying: Bool
}

enum PDFProtectService {
    static func protect(data: Data, name: String, output: URL, options o: ProtectOptions) throws {
        let doc = try DocTools.open(data: data, name: name)
        let owner = o.permissionsPassword.isEmpty ? (o.openPassword.isEmpty ? UUID().uuidString : o.openPassword) : o.permissionsPassword
        var opts: [PDFDocumentWriteOption: Any] = [.ownerPasswordOption: owner]
        if !o.openPassword.isEmpty { opts[.userPasswordOption] = o.openPassword }
        opts[PDFDocumentWriteOption(rawValue: kCGPDFContextAllowsPrinting as String)] = o.allowPrinting
        opts[PDFDocumentWriteOption(rawValue: kCGPDFContextAllowsCopying as String)] = o.allowCopying
        opts[PDFDocumentWriteOption(rawValue: kCGPDFContextEncryptionKeyLength as String)] = 128
        try DocTools.write(doc, to: output, options: opts)
    }
}

// MARK: - Hassas bilgileri kaldır

struct SanitizeOptions: Sendable {
    var metadata = true
    var comments = true
    var attachments = true
    var scripts = true
    var formData = false
    var links = false
}

enum PDFSanitizeService {
    static func sanitize(data: Data, name: String, output: URL, options o: SanitizeOptions) throws -> [String] {
        let src = try DocTools.open(data: data, name: name)
        let doc = (o.scripts || o.attachments || o.metadata) ? DocTools.rebuiltCopy(of: src) : src
        var report: [String] = []
        var removedAnn = 0, removedFiles = 0, clearedFields = 0, removedLinks = 0, removedActions = 0
        for i in 0..<doc.pageCount {
            guard let page = doc.page(at: i) else { continue }
            for a in page.annotations {
                let t = a.subtypeName
                let isMarkup = ["Text", "FreeText", "Highlight", "Underline", "StrikeOut", "Squiggly", "Ink", "Square", "Circle", "Line", "Polygon", "PolyLine", "Stamp", "Caret", "Popup", "Sound"].contains(t)
                if o.comments && isMarkup { page.removeAnnotation(a); removedAnn += 1; continue }
                if o.attachments && t == "FileAttachment" { page.removeAnnotation(a); removedFiles += 1; continue }
                if o.links && t == "Link" { page.removeAnnotation(a); removedLinks += 1; continue }
                if o.scripts, let action = a.action {
                    let safe = action is PDFActionURL || action is PDFActionGoTo || action is PDFActionNamed || action is PDFActionRemoteGoTo
                    if !safe { a.action = nil; removedActions += 1 }
                }
                if o.formData && t == "Widget" {
                    if a.widgetFieldType == .text { a.widgetStringValue = "" }
                    if a.widgetFieldType == .button && a.widgetControlType != .pushButtonControl { a.buttonWidgetState = .offState }
                    clearedFields += 1
                }
            }
        }
        if o.metadata {
            doc.documentAttributes = [:]
            report.append(String(localized: "Meta veriler (yazar, başlık, oluşturan uygulama) kaldırıldı"))
        }
        if o.scripts { report.append(String(localized: "Belge düzeyindeki komutlar kaldırıldı") + (removedActions > 0 ? String(localized: " (\(removedActions) eylem)") : "")) }
        if o.comments { report.append(String(localized: "\(removedAnn) yorum/açıklama kaldırıldı")) }
        if o.attachments { report.append(String(localized: "Gömülü dosyalar kaldırıldı") + (removedFiles > 0 ? String(localized: " (\(removedFiles) ek)") : "")) }
        if o.formData { report.append(String(localized: "\(clearedFields) form alanının değeri temizlendi")) }
        if o.links { report.append(String(localized: "\(removedLinks) bağlantı kaldırıldı")) }
        try DocTools.write(doc, to: output)
        return report
    }
}

// MARK: - PDF oluştur

enum PDFCreateService {
    /// Görsellerden (her görsel bir sayfa) PDF.
    static func fromImages(_ images: [UIImage], ocr: Bool) -> PDFDocument {
        let out = PDFDocument()
        for img in images {
            autoreleasepool {
                guard let cg = ImageAnnotation.makeCGImage(img) else { return }
                var lines: [OCRLine]?
                if ocr {
                    let w = PageRenderer.a4.width
                    let size = CGSize(width: w, height: (w * CGFloat(cg.height) / CGFloat(max(cg.width, 1))).rounded())
                    lines = try? PDFOCRService.recognize(cgImage: cg, pageSize: size)
                }
                if let p = PageRenderer.imagePage(cg, ocr: lines) { out.insert(p, at: out.pageCount) }
            }
        }
        return out
    }

    /// Metin, RTF, HTML veya Word (.docx) dosyasından PDF (UIKit yazdırma motoruyla sayfalanır).
    static func fromDocument(at url: URL) throws -> PDFDocument {
        let ext = url.pathExtension.lowercased()
        let attr: NSAttributedString
        if ["txt", "text", "md", "csv"].contains(ext) {
            let s = try SecurityScope.access(url) { try String(contentsOf: url, encoding: .utf8) }
            attr = NSAttributedString(string: s, attributes: [.font: UIFont.systemFont(ofSize: 12), .foregroundColor: UIColor.black])
        } else {
            var type: NSAttributedString.DocumentType = .rtf
            if ext == "html" || ext == "htm" { type = .html }
            if ext == "rtfd" { type = .rtfd }
            let data = try SecurityScope.access(url) { try Data(contentsOf: url) }
            if ext == "docx" || ext == "doc" {
                throw QPDFError.message(String(localized: "Word belgeleri iPhone'da doğrudan PDF'ye çevrilemiyor. Belgeyi Dosyalar'da açıp Paylaş > Yazdır > (iki parmakla büyüt) > Paylaş ile PDF olarak kaydedebilir veya Mac sürümünü kullanabilirsiniz."))
            }
            attr = try NSAttributedString(data: data, options: [.documentType: type], documentAttributes: nil)
        }
        return try paginate(attr)
    }

    /// Düz/zengin metni A4 sayfalara dizer.
    static func paginate(_ attr: NSAttributedString) throws -> PDFDocument {
        let formatter = UISimpleTextPrintFormatter(attributedText: attr)
        let renderer = UIPrintPageRenderer()
        renderer.addPrintFormatter(formatter, startingAtPageAt: 0)
        let paper = CGRect(origin: .zero, size: PageRenderer.a4)
        renderer.setValue(NSValue(cgRect: paper), forKey: "paperRect")
        renderer.setValue(NSValue(cgRect: paper.insetBy(dx: 50, dy: 56)), forKey: "printableRect")
        let data = NSMutableData()
        UIGraphicsBeginPDFContextToData(data, paper, nil)
        renderer.prepare(forDrawingPages: NSRange(location: 0, length: renderer.numberOfPages))
        for i in 0..<max(renderer.numberOfPages, 1) {
            UIGraphicsBeginPDFPage()
            if i < renderer.numberOfPages { renderer.drawPage(at: i, in: UIGraphicsGetPDFContextBounds()) }
        }
        UIGraphicsEndPDFContext()
        guard let doc = PDFDocument(data: data as Data), doc.pageCount > 0 else {
            throw QPDFError.message(String(localized: "PDF oluşturulamadı."))
        }
        return doc
    }

    static func blank(pages: Int = 1) -> PDFDocument {
        let out = PDFDocument()
        for _ in 0..<max(1, pages) {
            if let p = PageRenderer.blankPage() { out.insert(p, at: out.pageCount) }
        }
        return out
    }
}

// MARK: - Güvenlik kapsamlı dosya erişimi

/// Dosyalar uygulamasından gelen URL'ler güvenlik kapsamlıdır; okumadan önce erişim açılmalıdır.
enum SecurityScope {
    static func access<T>(_ url: URL, _ body: () throws -> T) rethrows -> T {
        let ok = url.startAccessingSecurityScopedResource()
        defer { if ok { url.stopAccessingSecurityScopedResource() } }
        return try body()
    }
}
