import Foundation
import AppKit
import PDFKit

enum ImageFormat: String, CaseIterable, Identifiable, Sendable {
    case jpeg, png, tiff
    var id: String { rawValue }
    var title: String {
        switch self {
        case .png: return "PNG"
        case .jpeg: return "JPEG"
        case .tiff: return "TIFF"
        }
    }
    var ext: String {
        switch self {
        case .png: return "png"
        case .jpeg: return "jpg"
        case .tiff: return "tiff"
        }
    }
}

enum ConvertTarget: String, CaseIterable, Identifiable, Sendable {
    case word, excel, powerpoint, image, text, rtf, html, searchable
    var id: String { rawValue }
    var title: String {
        switch self {
        case .word: return "Word (.docx)"
        case .excel: return "Excel (.xlsx)"
        case .powerpoint: return "PowerPoint (.pptx)"
        case .image: return "Görsel (PNG / JPEG)"
        case .text: return "Düz metin (.txt)"
        case .rtf: return "Zengin metin (.rtf)"
        case .html: return "Web sayfası (.html)"
        case .searchable: return "Aranabilir PDF (OCR)"
        }
    }
    var ext: String {
        switch self {
        case .word: return "docx"
        case .excel: return "xlsx"
        case .powerpoint: return "pptx"
        case .image: return "png"
        case .text: return "txt"
        case .rtf: return "rtf"
        case .html: return "html"
        case .searchable: return "pdf"
        }
    }
}

struct ConvertOptions: Sendable {
    var target: ConvertTarget = .word
    var imageFormat: ImageFormat = .png
    var dpi: CGFloat = 150
    var useOCR = true
    var preserveLayout = false
    var useLibreOffice = false
}

/// PDF'yi diğer biçimlere dönüştürür. Toplu işlem: her girdi dosyası için ayrı çıktı.
enum PDFConvertService {
    static func convert(input: URL, data: Data?, folder: URL, options o: ConvertOptions) throws -> [URL] {
        let base = input.baseName
        func target(_ ext: String, suffix: String = "") -> URL {
            var u = folder.appendingPathComponent("\(base)\(suffix).\(ext)")
            var n = 2
            while FileManager.default.fileExists(atPath: u.path) {
                u = folder.appendingPathComponent("\(base)\(suffix) \(n).\(ext)"); n += 1
            }
            return u
        }

        if o.target == .searchable {
            let out = target("pdf", suffix: "_ocr")
            let src: URL
            if let data {
                src = FileManager.default.temporaryDirectory.appendingPathComponent("qeniro-\(UUID().uuidString).pdf")
                try data.write(to: src)
            } else { src = input }
            _ = try PDFOCRService.makeSearchable(input: src, output: out, force: false)
            return [out]
        }

        if o.target == .word && o.useLibreOffice && LibreOfficeBridge.isAvailable && data == nil {
            let tmp = try LibreOfficeBridge.convert(input, to: "docx:MS Word 2007 XML", inputFilter: "writer_pdf_import")
            let out = target("docx")
            try FileManager.default.moveItem(at: tmp, to: out)
            return [out]
        }

        let doc: PDFDocument
        if let data { doc = try DocTools.open(data: data, name: input.lastPathComponent) } else { doc = try DocTools.open(input) }
        guard doc.pageCount > 0 else { throw QPDFError.noPages }

        switch o.target {
        case .image:
            let sub = folder.appendingPathComponent(base + "_gorseller", isDirectory: true)
            try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)
            var urls: [URL] = []
            for i in 0..<doc.pageCount {
                guard let page = doc.page(at: i) else { continue }
                let img = PageRenderer.displayImage(page: page, dpi: o.dpi)
                guard let data = encode(img, format: o.imageFormat) else { continue }
                let u = sub.appendingPathComponent(String(format: "%@_sayfa_%03d.%@", base, i + 1, o.imageFormat.ext))
                try data.write(to: u, options: .atomic)
                urls.append(u)
            }
            return urls
        case .text:
            var parts: [String] = []
            for i in 0..<doc.pageCount {
                guard let page = doc.page(at: i) else { continue }
                var s = page.string ?? ""
                if o.useOCR && !PDFOCRService.pageHasText(page) {
                    s = ((try? PDFOCRService.recognize(page: page)) ?? []).map { $0.text }.joined(separator: "\n")
                }
                parts.append(s)
            }
            let out = target("txt")
            try parts.joined(separator: "\n\u{000C}\n").write(to: out, atomically: true, encoding: .utf8)
            return [out]
        case .rtf:
            let m = NSMutableAttributedString()
            for i in 0..<doc.pageCount {
                if let a = doc.page(at: i)?.attributedString { m.append(a) }
                if i < doc.pageCount - 1 { m.append(NSAttributedString(string: "\n\u{000C}")) }
            }
            guard let rtf = m.rtf(from: NSRange(location: 0, length: m.length), documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]) else {
                throw QPDFError.message("RTF oluşturulamadı.")
            }
            let out = target("rtf")
            try rtf.write(to: out, options: .atomic)
            return [out]
        case .html:
            let m = NSMutableAttributedString()
            for i in 0..<doc.pageCount {
                if let a = doc.page(at: i)?.attributedString { m.append(a) }
                if i < doc.pageCount - 1 { m.append(NSAttributedString(string: "\n\n")) }
            }
            let html: Data
            do {
                html = try m.data(from: NSRange(location: 0, length: m.length),
                                  documentAttributes: [.documentType: NSAttributedString.DocumentType.html,
                                                       .characterEncoding: String.Encoding.utf8.rawValue])
            } catch {
                throw QPDFError.message("HTML oluşturulamadı.")
            }
            let out = target("html")
            try html.write(to: out, options: .atomic)
            return [out]
        case .word:
            let out = target("docx")
            try OfficeExportService.docx(doc: doc, preserveLayout: o.preserveLayout, useOCR: o.useOCR).write(to: out, options: .atomic)
            return [out]
        case .excel:
            let out = target("xlsx")
            try OfficeExportService.xlsx(doc: doc, useOCR: o.useOCR).write(to: out, options: .atomic)
            return [out]
        case .powerpoint:
            let out = target("pptx")
            try OfficeExportService.pptx(doc: doc, editableText: !o.preserveLayout, useOCR: o.useOCR).write(to: out, options: .atomic)
            return [out]
        case .searchable:
            return []
        }
    }

    static func encode(_ image: NSImage, format: ImageFormat, quality: Double = 0.9) -> Data? {
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let rep = NSBitmapImageRep(cgImage: cg)
        switch format {
        case .png: return rep.representation(using: .png, properties: [:])
        case .jpeg: return rep.representation(using: .jpeg, properties: [.compressionFactor: quality])
        case .tiff: return rep.representation(using: .tiff, properties: [:])
        }
    }
}
