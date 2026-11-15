import Foundation
import UIKit
import PDFKit
import CoreGraphics
import CoreText

// macOS'taki QeniroPDF/Services/PDFCore.swift dosyasının iOS (UIKit) karşılığı.
// Tür adları aynıdır; böylece paylaşılan servisler (OfficeExportService, PDFOCRService)
// iki platformda da değişmeden derlenir.

/// Uygulama genelindeki hata türü (Türkçe mesajlar).
enum QPDFError: LocalizedError {
    case cannotOpen(String)
    case locked(String)
    case writeFailed(String)
    case noPages
    case message(String)

    var errorDescription: String? {
        switch self {
        case .cannotOpen(let n): return "\"\(n)\" açılamadı. Dosya bozuk olabilir veya PDF değildir."
        case .locked(let n): return "\"\(n)\" şifreli. Önce şifresini girerek açın."
        case .writeFailed(let n): return "\"\(n)\" kaydedilemedi. Klasöre yazma izniniz olduğundan emin olun."
        case .noPages: return "İşlenecek sayfa bulunamadı."
        case .message(let m): return m
        }
    }
}

/// Uygulamanın eklediği açıklamaları tanımak için kullanılan etiketler.
enum QTag: String {
    case text, image, signature, initials, check, date, redact, link
    case note, markup, ink, shape
    /// "Uygula" ile sayfaya gömülen (düzleştirilen) türler.
    var flattensOnApply: Bool {
        switch self {
        case .redact, .link, .note, .markup, .ink, .shape: return false
        default: return true
        }
    }
    /// Seç aracıyla sürüklenerek taşınabilen öğeler.
    var isMovable: Bool {
        switch self {
        case .text, .image, .signature, .initials, .check, .date, .note, .shape, .redact: return true
        default: return false
        }
    }
    static let key = PDFAnnotationKey(rawValue: "/QTag")
}

/// Görsel veya imza içeren açıklama. PDFKit özel çizimleri dosyaya yazmadığından
/// kaydetme sırasında sayfaya düzleştirilir.
final class ImageAnnotation: PDFAnnotation {
    var image: UIImage {
        didSet { cgImageCache = ImageAnnotation.makeCGImage(image) }
    }
    var kind: QTag
    private var cgImageCache: CGImage?

    init(bounds: CGRect, image: UIImage, kind: QTag = .image) {
        self.image = image
        self.kind = kind
        self.cgImageCache = ImageAnnotation.makeCGImage(image)
        super.init(bounds: bounds, forType: .stamp, withProperties: nil)
    }

    required init?(coder: NSCoder) {
        self.image = UIImage()
        self.kind = .image
        self.cgImageCache = nil
        super.init(coder: coder)
    }

    /// UIImage her zaman CGImage taşımayabilir (CIImage tabanlı olabilir); gerekirse yeniden çizer.
    static func makeCGImage(_ image: UIImage) -> CGImage? {
        if let cg = image.cgImage, image.imageOrientation == .up { return cg }
        guard image.size.width > 0, image.size.height > 0 else { return nil }
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = image.scale
        format.opaque = false
        let r = UIGraphicsImageRenderer(size: image.size, format: format)
        return r.image { _ in image.draw(at: .zero) }.cgImage
    }

    override func draw(with box: PDFDisplayBox, in context: CGContext) {
        guard let cg = cgImageCache else { return }
        context.saveGState()
        context.interpolationQuality = .high
        context.draw(cg, in: bounds)
        context.restoreGState()
    }

    override func copy(with zone: NSZone? = nil) -> Any {
        ImageAnnotation(bounds: bounds, image: image, kind: kind)
    }
}

extension PDFAnnotation {
    /// "/Widget" veya "Widget" -> "Widget"
    var subtypeName: String {
        (type ?? "").trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }
    var isWidget: Bool { subtypeName == "Widget" }
    var isLink: Bool { subtypeName == "Link" }
    var isPopup: Bool { subtypeName == "Popup" }
    var isFreeText: Bool { subtypeName == "FreeText" }

    var persistedTag: QTag? {
        if let img = self as? ImageAnnotation { return img.kind }
        if let s = value(forAnnotationKey: QTag.key) as? String { return QTag(rawValue: s) }
        return nil
    }
}

/// Bir okunan OCR satırı (sayfa koordinatlarında, sol alt köken).
struct OCRLine: Sendable {
    var text: String
    var rect: CGRect
}

/// Sayfa oluşturma, görüntüleme ve düzleştirme yardımcıları.
enum PageRenderer {
    static let a4 = CGSize(width: 595.28, height: 841.89)
    static let letter = CGSize(width: 612, height: 792)

    /// Tek sayfalık PDF verisi üretir; `draw` sol alt kökenli (0,0,w,h) koordinatlarda çizer.
    static func singlePageData(size: CGSize, draw: (CGContext) -> Void) -> Data? {
        let data = NSMutableData()
        var box = CGRect(origin: .zero, size: size)
        guard let consumer = CGDataConsumer(data: data as CFMutableData),
              let ctx = CGContext(consumer: consumer, mediaBox: &box, nil) else { return nil }
        ctx.beginPDFPage(nil)
        draw(ctx)
        ctx.endPDFPage()
        ctx.closePDF()
        return data as Data
    }

    static func page(from data: Data?) -> PDFPage? {
        guard let data, let doc = PDFDocument(data: data) else { return nil }
        return doc.page(at: 0)
    }

    static func blankPage(size: CGSize = a4) -> PDFPage? {
        page(from: singlePageData(size: size) { ctx in
            ctx.setFillColor(CGColor(gray: 1, alpha: 1))
            ctx.fill(CGRect(origin: .zero, size: size))
        })
    }

    /// Sayfanın özgün içeriğini (açıklamalar hariç) bağlama çizer. Bağlam sayfa uzayında olmalı.
    static func drawOriginalContent(of page: PDFPage, in ctx: CGContext) {
        if let ref = page.pageRef {
            ctx.drawPDFPage(ref)
        } else {
            page.draw(with: .mediaBox, to: ctx)
        }
    }

    /// Sayfayı (döndürme uygulanmadan) bit eşlem olarak çizer.
    static func renderImage(page: PDFPage, dpi: CGFloat, includeAnnotations: [PDFAnnotation] = [], overlay: ((CGContext) -> Void)? = nil) -> CGImage? {
        let box = page.bounds(for: .mediaBox)
        let scale = dpi / 72.0
        let w = max(1, Int((box.width * scale).rounded()))
        let h = max(1, Int((box.height * scale).rounded()))
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.setFillColor(CGColor(gray: 1, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        ctx.interpolationQuality = .high
        ctx.scaleBy(x: scale, y: scale)
        ctx.translateBy(x: -box.minX, y: -box.minY)
        drawOriginalContent(of: page, in: ctx)
        for a in includeAnnotations { a.draw(with: .mediaBox, in: ctx) }
        overlay?(ctx)
        return ctx.makeImage()
    }

    /// Döndürme ve açıklamalar uygulanmış görüntü (dışa aktarma için).
    static func displayImage(page: PDFPage, dpi: CGFloat) -> UIImage {
        let b = page.bounds(for: .cropBox)
        var size = CGSize(width: b.width * dpi / 72, height: b.height * dpi / 72)
        if page.rotation % 180 != 0 { size = CGSize(width: size.height, height: size.width) }
        size = CGSize(width: max(1, size.width.rounded()), height: max(1, size.height.rounded()))
        // Ölçek 1: görüntü boyutu doğrudan piksel boyutudur (dpi'ye göre).
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let k = dpi / 72
        return UIGraphicsImageRenderer(size: size, format: format).image { rc in
            let ctx = rc.cgContext
            ctx.setFillColor(UIColor.white.cgColor)
            ctx.fill(CGRect(origin: .zero, size: size))
            // UIKit bağlamı yukarıdan aşağıdır; PDF sayfa uzayı aşağıdan yukarıdır.
            ctx.translateBy(x: 0, y: size.height)
            ctx.scaleBy(x: k, y: -k)
            // draw(with:to:) sayfanın döndürmesini ve açıklamalarını uygular.
            page.draw(with: .cropBox, to: ctx)
        }
    }

    /// Bir sayfayı yeniden kurar: özgün içerik (veya verilen görüntü) + düzleştirilen açıklamalar
    /// + isteğe bağlı ek çizim. `keep` içindeki açıklamaların kopyaları yeni sayfaya canlı olarak eklenir.
    static func rebuild(page: PDFPage,
                        contentImage: CGImage? = nil,
                        flatten: [PDFAnnotation] = [],
                        keep: [PDFAnnotation],
                        extra: ((CGContext) -> Void)? = nil) -> PDFPage? {
        let box = page.bounds(for: .mediaBox)
        let data = singlePageData(size: box.size) { ctx in
            if let img = contentImage {
                ctx.interpolationQuality = .high
                ctx.draw(img, in: CGRect(origin: .zero, size: box.size))
            } else {
                ctx.saveGState()
                ctx.translateBy(x: -box.minX, y: -box.minY)
                drawOriginalContent(of: page, in: ctx)
                ctx.restoreGState()
            }
            if !flatten.isEmpty {
                ctx.saveGState()
                ctx.translateBy(x: -box.minX, y: -box.minY)
                for a in flatten { a.draw(with: .mediaBox, in: ctx) }
                ctx.restoreGState()
            }
            extra?(ctx)
        }
        guard let newPage = self.page(from: data) else { return nil }
        newPage.rotation = page.rotation
        let crop = page.bounds(for: .cropBox)
        if crop != box {
            newPage.setBounds(crop.offsetBy(dx: -box.minX, dy: -box.minY), for: .cropBox)
        }
        for a in keep where !a.isPopup {
            guard let c = a.copy() as? PDFAnnotation else { continue }
            c.bounds = a.bounds.offsetBy(dx: -box.minX, dy: -box.minY)
            newPage.addAnnotation(c)
        }
        return newPage
    }

    /// OCR satırlarını görünmez (seçilebilir/aranabilir) metin olarak çizer.
    static func drawInvisibleText(_ lines: [OCRLine], in ctx: CGContext) {
        ctx.saveGState()
        ctx.setTextDrawingMode(.invisible)
        for l in lines {
            let text = l.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty, l.rect.width > 1, l.rect.height > 1 else { continue }
            let size = max(2, l.rect.height * 0.85)
            let font = CTFontCreateWithName("Helvetica" as CFString, size, nil)
            let attr = NSAttributedString(string: text, attributes: [NSAttributedString.Key(kCTFontAttributeName as String): font])
            let line = CTLineCreateWithAttributedString(attr)
            let width = CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
            ctx.saveGState()
            ctx.textMatrix = .identity
            ctx.translateBy(x: l.rect.minX, y: l.rect.minY + l.rect.height * 0.18)
            if width > 0 { ctx.scaleBy(x: l.rect.width / width, y: 1) }
            ctx.textPosition = .zero
            CTLineDraw(line, ctx)
            ctx.restoreGState()
        }
        ctx.restoreGState()
    }

    /// Bir görüntüyü sayfaya sığacak biçimde tek sayfalık PDF'ye çevirir (sayfa genişliği A4).
    /// `ocr` verilirse görünmez metin katmanı eklenir.
    static func imagePage(_ image: CGImage, ocr: [OCRLine]? = nil, pageWidth: CGFloat = a4.width) -> PDFPage? {
        let w = CGFloat(image.width), h = CGFloat(image.height)
        guard w > 0, h > 0 else { return nil }
        let size = CGSize(width: pageWidth, height: (pageWidth * h / w).rounded())
        return page(from: singlePageData(size: size) { ctx in
            ctx.interpolationQuality = .high
            ctx.draw(image, in: CGRect(origin: .zero, size: size))
            if let ocr { drawInvisibleText(ocr, in: ctx) }
        })
    }
}

/// Belge düzeyinde yardımcılar.
enum DocTools {
    /// URL'den PDF açar; şifreliyse hata verir.
    static func open(_ url: URL, password: String? = nil) throws -> PDFDocument {
        guard let doc = PDFDocument(url: url) else { throw QPDFError.cannotOpen(url.lastPathComponent) }
        if doc.isLocked {
            if let password, doc.unlock(withPassword: password) { return doc }
            throw QPDFError.locked(url.lastPathComponent)
        }
        return doc
    }

    static func open(data: Data, name: String) throws -> PDFDocument {
        guard let doc = PDFDocument(data: data) else { throw QPDFError.cannotOpen(name) }
        if doc.isLocked { throw QPDFError.locked(name) }
        return doc
    }

    static func write(_ doc: PDFDocument, to url: URL, options: [PDFDocumentWriteOption: Any]? = nil) throws {
        let ok: Bool
        if let options { ok = doc.write(to: url, withOptions: options) } else { ok = doc.write(to: url) }
        if !ok { throw QPDFError.writeFailed(url.lastPathComponent) }
    }

    /// Sayfa kopyalarından yeni (şifresiz, belge düzeyi ekleri/JS içermeyen) bir belge kurar.
    static func rebuiltCopy(of doc: PDFDocument, pages: [Int]? = nil) -> PDFDocument {
        let out = PDFDocument()
        let indices = pages ?? Array(0..<doc.pageCount)
        for i in indices {
            guard let p = doc.page(at: i), let c = p.copy() as? PDFPage else { continue }
            out.insert(c, at: out.pageCount)
        }
        return out
    }

    /// "1-3, 5, 8-" biçimindeki aralıkları 0 tabanlı sayfa dizileri olarak çözer.
    static func parseRanges(_ text: String, pageCount: Int) -> [[Int]] {
        var result: [[Int]] = []
        for part in text.split(whereSeparator: { $0 == "," || $0 == ";" }) {
            let token = part.trimmingCharacters(in: .whitespaces)
            if token.isEmpty { continue }
            if token.contains("-") {
                let comps = token.split(separator: "-", omittingEmptySubsequences: false).map { $0.trimmingCharacters(in: .whitespaces) }
                let start = Int(comps.first ?? "") ?? 1
                let end = comps.count > 1 ? (Int(comps[1]) ?? pageCount) : pageCount
                let s = max(1, min(start, pageCount)), e = max(1, min(end, pageCount))
                if s <= e { result.append(Array((s - 1)...(e - 1))) }
            } else if let n = Int(token), n >= 1, n <= pageCount {
                result.append([n - 1])
            }
        }
        return result
    }

    /// Uygulamanın geçici çıktı klasörü (paylaşım için). Her çağrıda yeni alt klasör.
    static func freshOutputFolder() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("QeniroCikti", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Uygulamanın Belgeler klasörü (Dosyalar uygulamasında "Qeniro PDF" olarak görünür).
    static var documentsFolder: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
    }

    /// Belgeler klasöründe çakışmayan dosya adı.
    static func uniqueDocumentURL(_ name: String, ext: String = "pdf") -> URL {
        let base = documentsFolder
        var u = base.appendingPathComponent("\(name).\(ext)")
        var n = 2
        while FileManager.default.fileExists(atPath: u.path) {
            u = base.appendingPathComponent("\(name) \(n).\(ext)"); n += 1
        }
        return u
    }
}
