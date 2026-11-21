import Foundation
import AppKit
import PDFKit
import CoreGraphics
import CoreText

/// Uygulama genelindeki hata türü (Türkçe mesajlar).
enum QPDFError: LocalizedError {
    case cannotOpen(String)
    case locked(String)
    case writeFailed(String)
    case noPages
    case message(String)

    var errorDescription: String? {
        switch self {
        case .cannotOpen(let n): return String(localized: "\"\(n)\" açılamadı. Dosya bozuk olabilir veya PDF değildir.")
        case .locked(let n): return String(localized: "\"\(n)\" şifreli. Önce Koruma aracıyla şifresini kaldırın veya belgeyi şifresiyle açın.")
        case .writeFailed(let n): return String(localized: "\"\(n)\" kaydedilemedi. Klasöre yazma izniniz olduğundan emin olun.")
        case .noPages: return String(localized: "İşlenecek sayfa bulunamadı.")
        case .message(let m): return m
        }
    }
}

/// Uygulamanın eklediği açıklamaları tanımak için kullanılan etiketler.
enum QTag: String {
    case text, image, signature, cover, redact, underline, link, checkbox, radio, field, date
    /// Yorum, işaretleme, çizim, şekil ve form hazırlama öğeleri (standart açıklamalar, canlı kalır).
    case note, markup, ink, shape, formField, sigField
    /// "Uygula" ile sayfaya gömülen (düzleştirilen) türler.
    var flattensOnApply: Bool {
        switch self {
        case .redact, .link, .note, .markup, .ink, .shape, .formField, .sigField: return false
        default: return true
        }
    }
    static let key = PDFAnnotationKey(rawValue: "/QTag")
}

/// Görsel veya imza içeren açıklama. PDFKit özel çizimleri dosyaya yazmadığından
/// kaydetme sırasında sayfaya düzleştirilir.
final class ImageAnnotation: PDFAnnotation {
    var image: NSImage
    var kind: QTag

    init(bounds: CGRect, image: NSImage, kind: QTag = .image) {
        self.image = image
        self.kind = kind
        super.init(bounds: bounds, forType: .stamp, withProperties: nil)
    }

    required init?(coder: NSCoder) {
        self.image = NSImage(size: NSSize(width: 1, height: 1))
        self.kind = .image
        super.init(coder: coder)
    }

    override func draw(with box: PDFDisplayBox, in context: CGContext) {
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return }
        context.saveGState()
        context.interpolationQuality = .high
        context.draw(cg, in: bounds)
        context.restoreGState()
    }

    override func copy(with zone: NSZone? = nil) -> Any {
        let c = ImageAnnotation(bounds: bounds, image: image, kind: kind)
        return c
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
    /// `overlay` sayfa uzayında ek çizim yapar (ör. sansür kutuları).
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
    static func displayImage(page: PDFPage, dpi: CGFloat) -> NSImage {
        let b = page.bounds(for: .cropBox)
        var size = CGSize(width: b.width * dpi / 72, height: b.height * dpi / 72)
        if page.rotation % 180 != 0 { size = CGSize(width: size.height, height: size.width) }
        return page.thumbnail(of: size, for: .cropBox)
    }

    /// Bir sayfayı yeniden kurar: özgün içerik (veya verilen görüntü) + düzleştirilen açıklamalar
    /// + isteğe bağlı ek çizim. `keep` içindeki açıklamaların kopyaları yeni sayfaya canlı olarak eklenir.
    /// Özgün sayfa değiştirilmez.
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
            let font = NSFont(name: "Helvetica", size: size) ?? NSFont.systemFont(ofSize: size)
            let attr = NSAttributedString(string: text, attributes: [.font: font])
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

    /// NSAttributedString'i Core Graphics bağlamına çizer (sol alt köken).
    static func drawAttributed(_ string: NSAttributedString, in rect: CGRect, ctx: CGContext) {
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
        string.draw(with: rect, options: [.usesLineFragmentOrigin, .usesFontLeading])
        NSGraphicsContext.restoreGraphicsState()
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
}
