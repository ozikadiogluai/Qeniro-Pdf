import Foundation
import AppKit
import PDFKit
import UniformTypeIdentifiers

/// Görsellerden, metinden, panodan ve Office/iWork dosyalarından PDF oluşturur.
@MainActor
enum PDFCreateService {
    static let imageExtensions: Set<String> = ["png", "jpg", "jpeg", "heic", "heif", "tif", "tiff", "gif", "bmp", "webp"]
    static let textExtensions: Set<String> = ["txt", "rtf", "rtfd", "docx", "doc", "odt", "html", "htm", "md", "wordml"]
    static let libreOfficeExtensions: Set<String> = ["docx", "doc", "odt", "xlsx", "xls", "ods", "pptx", "ppt", "odp", "pages", "numbers", "key"]

    /// Karışık dosya listesinden tek PDF oluşturur.
    static func create(from urls: [URL], fitToA4: Bool) throws -> PDFDocument {
        let out = PDFDocument()
        for url in urls {
            let ext = url.pathExtension.lowercased()
            if ext == "pdf" {
                let d = try DocTools.open(url)
                for i in 0..<d.pageCount { if let p = d.page(at: i)?.copy() as? PDFPage { out.insert(p, at: out.pageCount) } }
            } else if imageExtensions.contains(ext) {
                guard let img = NSImage(contentsOf: url) else { throw QPDFError.cannotOpen(url.lastPathComponent) }
                if let p = imagePage(img, fitToA4: fitToA4) { out.insert(p, at: out.pageCount) }
            } else if LibreOfficeBridge.isAvailable && libreOfficeExtensions.contains(ext),
                      let pdfURL = try? LibreOfficeBridge.convert(url, to: "pdf") {
                let d = try DocTools.open(pdfURL)
                for i in 0..<d.pageCount { if let p = d.page(at: i)?.copy() as? PDFPage { out.insert(p, at: out.pageCount) } }
            } else if textExtensions.contains(ext) {
                let attr = try loadAttributed(url)
                try append(attributed: attr, to: out)
            } else if ["xlsx", "xls", "pptx", "ppt", "pages", "numbers", "key", "ods", "odp"].contains(ext) {
                throw QPDFError.message(String(localized: "\"\(url.lastPathComponent)\" için LibreOffice gerekir (ücretsiz: libreoffice.org). Alternatif: dosyayı kendi uygulamasında açıp Dosya > PDF Olarak Dışa Aktar'ı kullanın."))
            } else {
                throw QPDFError.message(String(localized: "\"\(url.lastPathComponent)\" desteklenmeyen bir dosya türü."))
            }
        }
        guard out.pageCount > 0 else { throw QPDFError.noPages }
        return out
    }

    static func imagePage(_ img: NSImage, fitToA4: Bool) -> PDFPage? {
        guard fitToA4 else { return PDFPage(image: img) }
        guard let cg = img.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return PDFPage(image: img) }
        let landscape = img.size.width > img.size.height
        let size = landscape ? CGSize(width: PageRenderer.a4.height, height: PageRenderer.a4.width) : PageRenderer.a4
        let margin: CGFloat = 24
        let avail = CGSize(width: size.width - margin * 2, height: size.height - margin * 2)
        let s = min(avail.width / max(img.size.width, 1), avail.height / max(img.size.height, 1))
        let w = img.size.width * s, h = img.size.height * s
        let rect = CGRect(x: (size.width - w) / 2, y: (size.height - h) / 2, width: w, height: h)
        return PageRenderer.page(from: PageRenderer.singlePageData(size: size) { ctx in
            ctx.setFillColor(CGColor(gray: 1, alpha: 1))
            ctx.fill(CGRect(origin: .zero, size: size))
            ctx.interpolationQuality = .high
            ctx.draw(cg, in: rect)
        })
    }

    static func loadAttributed(_ url: URL) throws -> NSAttributedString {
        let ext = url.pathExtension.lowercased()
        if ext == "txt" || ext == "md" {
            let text = (try? String(contentsOf: url, encoding: .utf8)) ?? (try? String(contentsOf: url, encoding: .isoLatin1)) ?? ""
            return plain(text)
        }
        do {
            let attr = try NSAttributedString(url: url, options: [:], documentAttributes: nil)
            return forceDarkText(attr)
        } catch {
            throw QPDFError.message(String(localized: "\"\(url.lastPathComponent)\" okunamadı: \(error.localizedDescription)"))
        }
    }

    static func plain(_ text: String, size: CGFloat = 12) -> NSAttributedString {
        let p = NSMutableParagraphStyle()
        p.lineSpacing = 2
        return NSAttributedString(string: text, attributes: [
            .font: NSFont(name: "Helvetica", size: size) ?? NSFont.systemFont(ofSize: size),
            .foregroundColor: NSColor.black,
            .paragraphStyle: p
        ])
    }

    /// Koyu temada metnin beyaz çıkmasını önler.
    private static func forceDarkText(_ s: NSAttributedString) -> NSAttributedString {
        let m = NSMutableAttributedString(attributedString: s)
        m.enumerateAttribute(.foregroundColor, in: NSRange(location: 0, length: m.length)) { value, range, _ in
            if value == nil { m.addAttribute(.foregroundColor, value: NSColor.black, range: range) }
        }
        return m
    }

    /// Biçimli metni A4 sayfalara dizerek PDF verisi üretir.
    static func pdfData(from attributed: NSAttributedString) -> Data? {
        let paper = PageRenderer.a4
        let margin: CGFloat = 56
        let info = NSPrintInfo(dictionary: [:])
        info.paperSize = paper
        info.topMargin = margin
        info.bottomMargin = margin
        info.leftMargin = margin
        info.rightMargin = margin
        info.horizontalPagination = .fit
        info.verticalPagination = .automatic
        info.isHorizontallyCentered = false
        info.isVerticallyCentered = false
        let width = paper.width - margin * 2
        let tv = NSTextView(frame: NSRect(x: 0, y: 0, width: width, height: 10))
        tv.isEditable = false
        tv.drawsBackground = true
        tv.backgroundColor = .white
        tv.textContainerInset = .zero
        tv.textContainer?.lineFragmentPadding = 0
        tv.isVerticallyResizable = true
        tv.isHorizontallyResizable = false
        tv.textContainer?.widthTracksTextView = true
        tv.textContainer?.containerSize = NSSize(width: width, height: CGFloat.greatestFiniteMagnitude)
        tv.textStorage?.setAttributedString(attributed)
        if let lm = tv.layoutManager, let tc = tv.textContainer {
            lm.ensureLayout(for: tc)
            let used = lm.usedRect(for: tc)
            tv.frame = NSRect(x: 0, y: 0, width: width, height: max(used.height + 4, paper.height - margin * 2))
        }
        let data = NSMutableData()
        let op = NSPrintOperation.pdfOperation(with: tv, inside: tv.bounds, to: data, printInfo: info)
        op.showsPrintPanel = false
        op.showsProgressPanel = false
        guard op.run(), data.length > 0 else { return nil }
        return data as Data
    }

    static func append(attributed: NSAttributedString, to out: PDFDocument) throws {
        guard let data = pdfData(from: attributed), let doc = PDFDocument(data: data) else {
            throw QPDFError.message(String(localized: "Metin PDF'e dönüştürülemedi."))
        }
        for i in 0..<doc.pageCount { if let p = doc.page(at: i)?.copy() as? PDFPage { out.insert(p, at: out.pageCount) } }
    }

    static func fromText(_ text: String) throws -> PDFDocument {
        let out = PDFDocument()
        try append(attributed: plain(text), to: out)
        return out
    }

    static func blank(count: Int, size: CGSize) -> PDFDocument {
        let out = PDFDocument()
        for _ in 0..<max(1, count) {
            if let p = PageRenderer.blankPage(size: size) { out.insert(p, at: out.pageCount) }
        }
        return out
    }

    /// Panodaki PDF, görsel veya metinden belge oluşturur.
    static func fromClipboard() throws -> PDFDocument {
        let pb = NSPasteboard.general
        if let data = pb.data(forType: .pdf), let d = PDFDocument(data: data) { return d }
        if let images = pb.readObjects(forClasses: [NSImage.self], options: nil) as? [NSImage], !images.isEmpty {
            let out = PDFDocument()
            for img in images { if let p = imagePage(img, fitToA4: true) { out.insert(p, at: out.pageCount) } }
            if out.pageCount > 0 { return out }
        }
        if let rtf = pb.data(forType: .rtf), let attr = NSAttributedString(rtf: rtf, documentAttributes: nil) {
            let out = PDFDocument()
            try append(attributed: forceDarkText(attr), to: out)
            return out
        }
        if let s = pb.string(forType: .string), !s.isEmpty { return try fromText(s) }
        throw QPDFError.message(String(localized: "Panoda PDF'e dönüştürülebilecek içerik yok. Bir görsel, metin veya PDF kopyalayın."))
    }
}
