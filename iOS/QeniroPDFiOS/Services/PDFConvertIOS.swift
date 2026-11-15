import Foundation
import UIKit
import PDFKit

// macOS'taki QeniroPDF/Services/PDFConvertService.swift dosyasının iOS karşılığı.
// OfficeExportService (paylaşılan dosya) bu türdeki `encode` işlevini kullanır.

enum ImageFormat: String, CaseIterable, Identifiable, Sendable {
    case jpeg, png
    var id: String { rawValue }
    var title: String { self == .png ? "PNG" : "JPEG" }
    var ext: String { self == .png ? "png" : "jpg" }
}

/// Dönüştür panelindeki seçenekler (tasarımdaki sıra).
enum ConvertTarget: String, CaseIterable, Identifiable, Sendable {
    case word, powerpoint, excel, image, other
    var id: String { rawValue }
    var label: String {
        switch self {
        case .word: return "Microsoft Word"
        case .powerpoint: return "Microsoft PowerPoint"
        case .excel: return "Microsoft Excel"
        case .image: return "Görüntü (JPEG, PNG)"
        case .other: return "Diğer (RTF, TXT, HTML)"
        }
    }
    var badge: String {
        switch self {
        case .word: return "DOCX"
        case .powerpoint: return "PPTX"
        case .excel: return "XLSX"
        case .image: return "JPEG"
        case .other: return "RTF"
        }
    }
}

enum OtherTextFormat: String, CaseIterable, Identifiable, Sendable {
    case rtf, txt, html
    var id: String { rawValue }
    var title: String { rawValue.uppercased() }
}

struct ConvertOptions: Sendable {
    var target: ConvertTarget = .word
    var imageFormat: ImageFormat = .jpeg
    var otherFormat: OtherTextFormat = .rtf
    var dpi: CGFloat = 150
    var useOCR = true
    var preserveLayout = false

    /// Mavi düğmede gösterilen biçim adı.
    var formatName: String {
        switch target {
        case .image: return imageFormat == .png ? "PNG" : "JPEG"
        case .other: return otherFormat.title
        default: return target.badge
        }
    }

    /// "DOCX'e Dönüştür", "PNG'ye Dönüştür"… (Türkçe ek uyumu, harf harf okunuşa göre).
    var buttonTitle: String {
        let suffix: String
        switch formatName {
        case "PNG", "TXT": suffix = "'ye"
        default: suffix = "'e"
        }
        return formatName + suffix + " Dönüştür"
    }
}

enum PDFConvertService {
    /// Belgeyi seçilen biçime dönüştürür; çıktı dosyalarını `folder` içine yazar.
    static func convert(data: Data, baseName base: String, folder: URL, options o: ConvertOptions) throws -> [URL] {
        let doc = try DocTools.open(data: data, name: base)
        guard doc.pageCount > 0 else { throw QPDFError.noPages }
        func target(_ ext: String) -> URL { folder.appendingPathComponent("\(base).\(ext)") }

        switch o.target {
        case .image:
            var urls: [URL] = []
            for i in 0..<doc.pageCount {
                guard let page = doc.page(at: i) else { continue }
                try autoreleasepool {
                    let img = PageRenderer.displayImage(page: page, dpi: o.dpi)
                    guard let d = encode(img, format: o.imageFormat) else { return }
                    let u = folder.appendingPathComponent(String(format: "%@_sayfa_%03d.%@", base, i + 1, o.imageFormat.ext))
                    try d.write(to: u, options: .atomic)
                    urls.append(u)
                }
            }
            return urls
        case .other:
            switch o.otherFormat {
            case .txt:
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
            case .rtf, .html:
                let m = NSMutableAttributedString()
                for i in 0..<doc.pageCount {
                    guard let page = doc.page(at: i) else { continue }
                    if let a = page.attributedString, a.length > 0 {
                        m.append(a)
                    } else if o.useOCR {
                        let text = ((try? PDFOCRService.recognize(page: page)) ?? []).map { $0.text }.joined(separator: "\n")
                        m.append(NSAttributedString(string: text, attributes: [.font: UIFont.systemFont(ofSize: 12)]))
                    }
                    if i < doc.pageCount - 1 { m.append(NSAttributedString(string: o.otherFormat == .rtf ? "\n\u{000C}" : "\n\n")) }
                }
                let type: NSAttributedString.DocumentType = o.otherFormat == .rtf ? .rtf : .html
                var attrs: [NSAttributedString.DocumentAttributeKey: Any] = [.documentType: type]
                if type == .html { attrs[.characterEncoding] = String.Encoding.utf8.rawValue }
                let out = target(o.otherFormat.rawValue)
                do {
                    let d = try m.data(from: NSRange(location: 0, length: m.length), documentAttributes: attrs)
                    try d.write(to: out, options: .atomic)
                } catch {
                    throw QPDFError.message("\(o.otherFormat.title) oluşturulamadı.")
                }
                return [out]
            }
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
        }
    }

    static func encode(_ image: UIImage, format: ImageFormat, quality: Double = 0.9) -> Data? {
        switch format {
        case .png: return image.pngData()
        case .jpeg: return image.jpegData(compressionQuality: CGFloat(quality))
        }
    }
}

/// Tanınan metin dili (Dönüştür panelindeki seçim).
enum OCRLanguage: String, CaseIterable, Identifiable {
    case turkish = "tr-TR", english = "en-US", german = "de-DE", french = "fr-FR", spanish = "es-ES", italian = "it-IT"
    var id: String { rawValue }
    var title: String {
        switch self {
        case .turkish: return "Türkçe"
        case .english: return "İngilizce"
        case .german: return "Almanca"
        case .french: return "Fransızca"
        case .spanish: return "İspanyolca"
        case .italian: return "İtalyanca"
        }
    }
    /// Vision'a verilecek dil listesi (ikinci dil olarak İngilizce eklenir).
    var visionLanguages: [String] { self == .english ? ["en-US"] : [rawValue, "en-US"] }
}
