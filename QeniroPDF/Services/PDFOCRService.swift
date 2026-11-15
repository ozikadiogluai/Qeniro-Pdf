import Foundation
import PDFKit
import Vision
import CoreGraphics
#if os(macOS)
import AppKit
#endif

/// Vision ile metin tanıma (Türkçe + İngilizce).
enum PDFOCRService {
    private static let languageLock = NSLock()
    private static var storedLanguages = ["tr-TR", "en-US"]

    /// Tanınan metin dili (Dönüştür panelinden seçilir). İş parçacığı güvenli.
    static var preferredLanguages: [String] {
        get {
            languageLock.lock()
            defer { languageLock.unlock() }
            return storedLanguages
        }
        set {
            languageLock.lock()
            storedLanguages = newValue.isEmpty ? ["tr-TR", "en-US"] : newValue
            languageLock.unlock()
        }
    }

    static func recognize(cgImage: CGImage, pageSize: CGSize) throws -> [OCRLine] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        let supported = (try? request.supportedRecognitionLanguages()) ?? []
        let wanted = preferredLanguages.filter { supported.contains($0) }
        if wanted.isEmpty {
            request.automaticallyDetectsLanguage = true
        } else {
            request.recognitionLanguages = wanted
        }
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        try handler.perform([request])
        let observations = request.results ?? []
        var lines: [OCRLine] = []
        for obs in observations {
            guard let candidate = obs.topCandidates(1).first else { continue }
            let bb = obs.boundingBox
            let rect = CGRect(x: bb.minX * pageSize.width, y: bb.minY * pageSize.height,
                              width: bb.width * pageSize.width, height: bb.height * pageSize.height)
            lines.append(OCRLine(text: candidate.string, rect: rect))
        }
        return lines
    }

    static func recognize(page: PDFPage, dpi: CGFloat = 200) throws -> [OCRLine] {
        guard let img = PageRenderer.renderImage(page: page, dpi: dpi) else { return [] }
        return try recognize(cgImage: img, pageSize: page.bounds(for: .mediaBox).size)
    }

    static func pageHasText(_ page: PDFPage) -> Bool {
        let s = (page.string ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return s.count > 8
    }

    /// Her sayfa için OCR satırları; atlanan sayfalar nil.
    static func recognizeAll(data: Data, skipPagesWithText: Bool, progress: (@Sendable (Double) -> Void)? = nil) throws -> [[OCRLine]?] {
        let doc = try DocTools.open(data: data, name: "Belge")
        var out: [[OCRLine]?] = []
        for i in 0..<doc.pageCount {
            guard let page = doc.page(at: i) else { out.append(nil); continue }
            if skipPagesWithText && pageHasText(page) {
                out.append(nil)
            } else {
                out.append(try recognize(page: page))
            }
            progress?(Double(i + 1) / Double(max(doc.pageCount, 1)))
        }
        return out
    }

    /// Dosyayı OCR'lar ve aranabilir PDF olarak yazar.
    static func makeSearchable(input: URL, output: URL, force: Bool) throws -> Int {
        let doc = try DocTools.open(input)
        var count = 0
        for i in 0..<doc.pageCount {
            guard let page = doc.page(at: i) else { continue }
            if !force && pageHasText(page) { continue }
            let lines = try recognize(page: page)
            guard !lines.isEmpty else { continue }
            if let np = PageRenderer.rebuild(page: page, keep: page.annotations, extra: { ctx in
                PageRenderer.drawInvisibleText(lines, in: ctx)
            }) {
                doc.removePage(at: i)
                doc.insert(np, at: i)
                count += 1
            }
        }
        try DocTools.write(doc, to: output)
        return count
    }
}
