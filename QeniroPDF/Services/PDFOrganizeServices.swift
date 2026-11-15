import Foundation
import PDFKit
import Quartz
import AppKit
import ImageIO

// MARK: - Birleştir

enum PDFMergeService {
    /// PDF dosyalarını verilen sırayla birleştirir.
    static func merge(_ urls: [URL], to output: URL) throws -> Int {
        guard !urls.isEmpty else { throw QPDFError.noPages }
        let out = PDFDocument()
        for url in urls {
            let doc = try DocTools.open(url)
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
    static func split(input: URL, data: Data?, mode: SplitMode, folder: URL, baseName: String) throws -> [URL] {
        let doc: PDFDocument
        if let data { doc = try DocTools.open(data: data, name: baseName) } else { doc = try DocTools.open(input) }
        let n = doc.pageCount
        guard n > 0 else { throw QPDFError.noPages }
        var groups: [[Int]] = []
        switch mode {
        case .ranges(let text):
            groups = DocTools.parseRanges(text, pageCount: n)
            if groups.isEmpty { throw QPDFError.message("Sayfa aralığı anlaşılamadı. Örnek: 1-3, 5, 8-") }
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
            if g.count == 1 { label = "s\(g[0] + 1)" } else { label = "s\(g.first! + 1)-\(g.last! + 1)" }
            var url = folder.appendingPathComponent("\(baseName)_\(k + 1)_\(label).pdf")
            var c = 2
            while FileManager.default.fileExists(atPath: url.path) {
                url = folder.appendingPathComponent("\(baseName)_\(k + 1)_\(label) \(c).pdf"); c += 1
            }
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
        case .low: return "Düşük (en iyi kalite)"
        case .medium: return "Orta (önerilen)"
        case .high: return "Yüksek (en küçük boyut)"
        }
    }
    var quality: Double { self == .low ? 0.75 : (self == .medium ? 0.55 : 0.35) }
    var scale: Double { self == .low ? 0.85 : (self == .medium ? 0.6 : 0.4) }
    var dpi: CGFloat { self == .low ? 150 : (self == .medium ? 110 : 80) }
}

struct CompressResult: Sendable {
    var before: Int64
    var after: Int64
    var output: URL
    var note: String?
}

enum PDFCompressService {
    /// Sistemdeki "Reduce File Size" Quartz filtresini seviyeye göre ayarlayıp geçici dosyaya yazar.
    static func makeFilterURL(level: CompressionLevel) -> URL? {
        var plist: [String: Any] = [:]
        let system = URL(fileURLWithPath: "/System/Library/Filters/Reduce File Size.qfilter")
        if let data = try? Data(contentsOf: system),
           let obj = try? PropertyListSerialization.propertyList(from: data, options: [.mutableContainersAndLeaves], format: nil) as? [String: Any] {
            plist = obj
        } else {
            plist = ["Domains": ["Applications": true, "Printing": true], "FilterType": 1, "Name": "Qeniro Sıkıştır"]
        }
        var filterData = plist["FilterData"] as? [String: Any] ?? [:]
        var color = filterData["ColorSettings"] as? [String: Any] ?? [:]
        var image = color["ImageSettings"] as? [String: Any] ?? [:]
        image["Compression Quality"] = level.quality
        image["ImageCompression"] = "ImageJPEGCompress"
        var scale = image["ImageScaleSettings"] as? [String: Any] ?? [:]
        scale["ImageScaleFactor"] = level.scale
        scale["ImageResolution"] = Int(level.dpi)
        scale["ImageScaleInterpolate"] = true
        image["ImageScaleSettings"] = scale
        color["ImageSettings"] = image
        filterData["ColorSettings"] = color
        plist["FilterData"] = filterData
        plist["Name"] = "Qeniro \(level.rawValue)"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("qeniro-\(level.rawValue).qfilter")
        guard let out = try? PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0) else { return nil }
        do { try out.write(to: url, options: .atomic) } catch { return nil }
        return url
    }

    static func compress(input: URL, data: Data?, output: URL, level: CompressionLevel, rasterize: Bool) throws -> CompressResult {
        let before: Int64 = data.map { Int64($0.count) } ?? Fmt.fileSize(of: input)
        let doc: PDFDocument
        if let data { doc = try DocTools.open(data: data, name: input.lastPathComponent) } else { doc = try DocTools.open(input) }
        var note: String?

        if rasterize {
            try rasterizeAll(doc: doc, level: level, output: output)
            note = "Sayfalar görüntüye çevrildi; metin seçilebilirliği OCR ile geri eklendi."
        } else {
            var wrote = false
            if let furl = makeFilterURL(level: level) {
                let filter: QuartzFilter? = QuartzFilter(url: furl)
                if let filter {
                    wrote = doc.write(to: output, withOptions: [PDFDocumentWriteOption(rawValue: "QuartzFilter"): filter])
                }
            }
            if !wrote { try DocTools.write(doc, to: output) }
        }
        let after = Fmt.fileSize(of: output)
        if after >= before && !rasterize {
            note = "Bu dosya zaten iyi sıkıştırılmış; boyut azaltılamadı. Daha fazla küçültmek için \"Sayfaları görüntüye çevir\" seçeneğini deneyin."
        }
        return CompressResult(before: before, after: after, output: output, note: note)
    }

    private static func rasterizeAll(doc: PDFDocument, level: CompressionLevel, output: URL) throws {
        let out = PDFDocument()
        for i in 0..<doc.pageCount {
            guard let page = doc.page(at: i) else { continue }
            guard let cg = PageRenderer.renderImage(page: page, dpi: level.dpi) else { continue }
            let rep = NSBitmapImageRep(cgImage: cg)
            guard let jpeg = rep.representation(using: .jpeg, properties: [.compressionFactor: level.quality]),
                  let src = CGImageSourceCreateWithData(jpeg as CFData, nil),
                  let jpgImage = CGImageSourceCreateImageAtIndex(src, 0, nil) else { continue }
            let lines = (try? PDFOCRService.recognize(cgImage: cg, pageSize: page.bounds(for: .mediaBox).size)) ?? []
            let keep = page.annotations.filter { $0.isLink }
            if let np = PageRenderer.rebuild(page: page, contentImage: jpgImage, keep: keep, extra: { ctx in
                PageRenderer.drawInvisibleText(lines, in: ctx)
            }) {
                out.insert(np, at: out.pageCount)
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
    static func protect(input: URL, data: Data?, output: URL, options o: ProtectOptions) throws {
        let doc: PDFDocument
        if let data { doc = try DocTools.open(data: data, name: input.lastPathComponent) } else { doc = try DocTools.open(input) }
        let owner = o.permissionsPassword.isEmpty ? (o.openPassword.isEmpty ? UUID().uuidString : o.openPassword) : o.permissionsPassword
        var opts: [PDFDocumentWriteOption: Any] = [.ownerPasswordOption: owner]
        if !o.openPassword.isEmpty { opts[.userPasswordOption] = o.openPassword }
        opts[PDFDocumentWriteOption(rawValue: kCGPDFContextAllowsPrinting as String)] = o.allowPrinting
        opts[PDFDocumentWriteOption(rawValue: kCGPDFContextAllowsCopying as String)] = o.allowCopying
        opts[PDFDocumentWriteOption(rawValue: kCGPDFContextEncryptionKeyLength as String)] = 128
        try DocTools.write(doc, to: output, options: opts)
    }

    static func removePassword(input: URL, password: String, output: URL) throws {
        guard let doc = PDFDocument(url: input) else { throw QPDFError.cannotOpen(input.lastPathComponent) }
        if doc.isLocked || doc.isEncrypted {
            guard doc.unlock(withPassword: password) else { throw QPDFError.message("Şifre yanlış.") }
        }
        let out = DocTools.rebuiltCopy(of: doc)
        if let attrs = doc.documentAttributes { out.documentAttributes = attrs }
        try DocTools.write(out, to: output)
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
    static func sanitize(input: URL, data: Data?, output: URL, options o: SanitizeOptions) throws -> [String] {
        let src: PDFDocument
        if let data { src = try DocTools.open(data: data, name: input.lastPathComponent) } else { src = try DocTools.open(input) }
        // Sayfa kopyalarından yeniden kurmak; belge düzeyindeki JavaScript, gömülü dosyalar,
        // XMP meta verisi ve diğer katalog öğelerini dışarıda bırakır.
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
            report.append("Meta veriler (yazar, başlık, oluşturan uygulama, XMP) kaldırıldı")
        }
        if o.scripts { report.append("Belge düzeyindeki komutlar ve gömülü JavaScript kaldırıldı" + (removedActions > 0 ? " (\(removedActions) eylem)" : "")) }
        if o.comments { report.append("\(removedAnn) yorum/açıklama kaldırıldı") }
        if o.attachments { report.append("Gömülü dosyalar kaldırıldı" + (removedFiles > 0 ? " (\(removedFiles) ek)" : "")) }
        if o.formData { report.append("\(clearedFields) form alanının değeri temizlendi") }
        if o.links { report.append("\(removedLinks) bağlantı kaldırıldı") }
        try DocTools.write(doc, to: output)
        return report
    }
}
