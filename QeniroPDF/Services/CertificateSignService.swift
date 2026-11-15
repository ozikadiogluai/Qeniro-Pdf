import Foundation
import AppKit
import PDFKit
import Security

/// Anahtar Zinciri'ndeki bir imzalama kimliği (sertifika + özel anahtar).
struct SigningIdentity: Identifiable {
    let id = UUID()
    let identity: SecIdentity
    let name: String
    let issuer: String
    let expires: Date?
}

/// PAdES uyumlu (adbe.pkcs7.detached) dijital imza. PDF'in sonuna artımlı güncelleme eklenir,
/// imza CMS (SHA-256) olarak Security çerçevesinin CMSEncoder'ı ile üretilir.
enum CertificateSignService {

    static func availableIdentities() -> [SigningIdentity] {
        let query: [String: Any] = [
            kSecClass as String: kSecClassIdentity,
            kSecReturnRef as String: true,
            kSecMatchLimit as String: kSecMatchLimitAll
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let items = result as? [Any] else { return [] }
        var out: [SigningIdentity] = []
        for item in items {
            let identity = item as! SecIdentity
            var cert: SecCertificate?
            guard SecIdentityCopyCertificate(identity, &cert) == errSecSuccess, let cert else { continue }
            let name = (SecCertificateCopySubjectSummary(cert) as String?) ?? "Adsız sertifika"
            var issuer = ""
            var expires: Date?
            if let values = SecCertificateCopyValues(cert, [kSecOIDX509V1IssuerName, kSecOIDX509V1ValidityNotAfter] as CFArray, nil) as? [String: Any] {
                if let iss = values[kSecOIDX509V1IssuerName as String] as? [String: Any],
                   let list = iss[kSecPropertyKeyValue as String] as? [[String: Any]] {
                    issuer = list.compactMap { $0[kSecPropertyKeyValue as String] as? String }.joined(separator: ", ")
                }
                if let na = values[kSecOIDX509V1ValidityNotAfter as String] as? [String: Any],
                   let v = na[kSecPropertyKeyValue as String] as? NSNumber {
                    expires = Date(timeIntervalSinceReferenceDate: v.doubleValue)
                }
            }
            out.append(SigningIdentity(identity: identity, name: name, issuer: issuer, expires: expires))
        }
        return out.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    enum Corner: String, CaseIterable, Identifiable {
        case bottomRight = "Sağ alt", bottomLeft = "Sol alt", topRight = "Sağ üst", topLeft = "Sol üst"
        var id: String { rawValue }
    }

    /// Görünür imza kutusunu sayfaya gömer.
    @MainActor
    static func stampAppearance(doc: PDFDocument, pageIndex: Int, corner: Corner, signer: String, reason: String, location: String) {
        guard let page = doc.page(at: pageIndex) else { return }
        let crop = page.bounds(for: .cropBox)
        let media = page.bounds(for: .mediaBox)
        let w: CGFloat = 220, h: CGFloat = 64, m: CGFloat = 24
        var r = CGRect(x: crop.maxX - w - m, y: crop.minY + m, width: w, height: h)
        switch corner {
        case .bottomRight: break
        case .bottomLeft: r.origin.x = crop.minX + m
        case .topRight: r.origin.y = crop.maxY - h - m
        case .topLeft: r.origin = CGPoint(x: crop.minX + m, y: crop.maxY - h - m)
        }
        let local = r.offsetBy(dx: -media.minX, dy: -media.minY)
        var text = "Dijital olarak imzalayan:\n\(signer)\nTarih: \(Fmt.dateTime())"
        if !reason.isEmpty { text += "\nNeden: \(reason)" }
        if !location.isEmpty { text += " · Yer: \(location)" }
        let para = NSMutableParagraphStyle()
        para.lineSpacing = 1
        let attr = NSAttributedString(string: text, attributes: [
            .font: NSFont.systemFont(ofSize: 8),
            .foregroundColor: NSColor(srgbRed: 0.10, green: 0.23, blue: 0.54, alpha: 1),
            .paragraphStyle: para
        ])
        guard let np = PageRenderer.rebuild(page: page, keep: page.annotations, extra: { ctx in
            ctx.setStrokeColor(CGColor(srgbRed: 0.18, green: 0.42, blue: 0.89, alpha: 1))
            ctx.setFillColor(CGColor(srgbRed: 0.93, green: 0.95, blue: 1, alpha: 0.9))
            ctx.setLineWidth(1)
            ctx.fill(local)
            ctx.stroke(local)
            PageRenderer.drawAttributed(attr, in: local.insetBy(dx: 6, dy: 5), ctx: ctx)
        }) else { return }
        doc.removePage(at: pageIndex)
        doc.insert(np, at: pageIndex)
    }

    // MARK: - İmzalama

    private static let contentsPlaceholderBytes = 8192

    static func sign(pdf original: Data, identity: SecIdentity, name: String, reason: String, location: String) throws -> Data {
        guard let text = String(data: original, encoding: .isoLatin1) else { throw QPDFError.message("PDF okunamadı.") }
        let ns = text as NSString

        // 1) Son xref ve trailer bilgileri
        let sx = ns.range(of: "startxref", options: .backwards)
        guard sx.location != NSNotFound else { throw QPDFError.message("PDF yapısı tanınamadı (startxref yok).") }
        let afterSX = ns.substring(from: sx.location + sx.length)
        guard let prevXref = Int(afterSX.trimmingCharacters(in: .whitespacesAndNewlines).components(separatedBy: .whitespacesAndNewlines).first ?? "") else {
            throw QPDFError.message("PDF yapısı tanınamadı (xref konumu).")
        }
        if prevXref < ns.length {
            let probe = ns.substring(with: NSRange(location: prevXref, length: min(4, ns.length - prevXref)))
            guard probe == "xref" else {
                throw QPDFError.message("Bu PDF sıkıştırılmış çapraz başvuru akışı kullanıyor; sertifika imzası için desteklenmiyor.")
            }
        }
        guard let root = lastMatch(in: text, pattern: "/Root\\s+(\\d+)\\s+(\\d+)\\s+R"),
              let rootNum = Int(root[1]), let rootGen = Int(root[2]) else {
            throw QPDFError.message("Belge kataloğu bulunamadı.")
        }
        guard let sizeMatch = lastMatch(in: text, pattern: "/Size\\s+(\\d+)"), let size = Int(sizeMatch[1]) else {
            throw QPDFError.message("Belge nesne sayısı bulunamadı.")
        }
        let info = lastMatch(in: text, pattern: "/Info\\s+(\\d+\\s+\\d+\\s+R)")?[1]

        // 2) Katalog sözlüğünü bul
        guard let objStart = lastRange(in: text, pattern: "(?<![0-9])\(rootNum)\\s+\(rootGen)\\s+obj") else {
            throw QPDFError.message("Katalog nesnesi bulunamadı.")
        }
        let dictOpen = ns.range(of: "<<", options: [], range: NSRange(location: objStart.location, length: ns.length - objStart.location))
        guard dictOpen.location != NSNotFound, let dictEnd = matchingDictEnd(ns, from: dictOpen.location) else {
            throw QPDFError.message("Katalog sözlüğü okunamadı.")
        }
        let catalogDict = ns.substring(with: NSRange(location: dictOpen.location, length: dictEnd - dictOpen.location))
        if catalogDict.contains("/AcroForm") {
            throw QPDFError.message("Bu belge form alanları içeriyor. Önce \"İmzala ve Doldur > Uygula\" ile formu düzleştirip kaydedin, sonra sertifika ile imzalayın.")
        }

        // 3) Yeni nesneler
        let sigNum = size, fieldNum = size + 1, acroNum = size + 2
        let placeholderHex = String(repeating: "0", count: contentsPlaceholderBytes * 2)
        let byteRangePlaceholder = "/ByteRange [0 ********** ********** **********]"
        let date = pdfDate(Date())
        var sigObj = "\(sigNum) 0 obj\n<< /Type /Sig /Filter /Adobe.PPKLite /SubFilter /adbe.pkcs7.detached "
        sigObj += "\(byteRangePlaceholder) /Contents <\(placeholderHex)> /M (\(date)) "
        sigObj += "/Name \(pdfText(name)) "
        if !reason.isEmpty { sigObj += "/Reason \(pdfText(reason)) " }
        if !location.isEmpty { sigObj += "/Location \(pdfText(location)) " }
        sigObj += ">>\nendobj\n"
        let fieldObj = "\(fieldNum) 0 obj\n<< /Type /Annot /Subtype /Widget /FT /Sig /T \(pdfText("Qeniro İmza")) /F 132 /Rect [0 0 0 0] /V \(sigNum) 0 R >>\nendobj\n"
        let acroObj = "\(acroNum) 0 obj\n<< /Fields [\(fieldNum) 0 R] /SigFlags 3 >>\nendobj\n"
        let newCatalogDict = String(catalogDict.dropLast(2)) + " /AcroForm \(acroNum) 0 R >>"
        let catalogObj = "\(rootNum) \(rootGen) obj\n\(newCatalogDict)\nendobj\n"

        // 4) Artımlı güncellemeyi oluştur
        var appended = original.last == 0x0A ? "" : "\n"
        var offsets: [Int: Int] = [:]
        func emit(_ num: Int, _ body: String) {
            offsets[num] = original.count + appended.utf8.count
            appended += body
        }
        emit(rootNum, catalogObj)
        emit(sigNum, sigObj)
        emit(fieldNum, fieldObj)
        emit(acroNum, acroObj)
        let xrefOffset = original.count + appended.utf8.count
        func entry(_ off: Int, _ gen: Int) -> String { String(format: "%010ld %05ld n \n", off, gen) }
        var xref = "xref\n0 1\n0000000000 65535 f \n"
        xref += "\(rootNum) 1\n" + entry(offsets[rootNum]!, rootGen)
        xref += "\(sigNum) 3\n" + entry(offsets[sigNum]!, 0) + entry(offsets[fieldNum]!, 0) + entry(offsets[acroNum]!, 0)
        var trailer = "trailer\n<< /Size \(size + 3) /Root \(rootNum) \(rootGen) R /Prev \(prevXref)"
        if let info { trailer += " /Info \(info)" }
        trailer += " >>\nstartxref\n\(xrefOffset)\n%%EOF\n"
        appended += xref + trailer

        var data = original
        data.append(Data(appended.utf8))

        // 5) ByteRange'i doldur
        guard let contentsTag = data.range(of: Data("/Contents <".utf8), options: .backwards, in: original.count..<data.count) else {
            throw QPDFError.message("İmza alanı oluşturulamadı.")
        }
        let start = contentsTag.upperBound - 1               // '<' konumu
        let end = start + 1 + placeholderHex.count + 1        // '>' sonrası
        let byteRange = "/ByteRange [0 \(pad(start)) \(pad(end)) \(pad(data.count - end))]"
        guard byteRange.utf8.count == byteRangePlaceholder.utf8.count,
              let brRange = data.range(of: Data(byteRangePlaceholder.utf8), options: [], in: original.count..<data.count) else {
            throw QPDFError.message("Bayt aralığı yazılamadı.")
        }
        data.replaceSubrange(brRange, with: Data(byteRange.utf8))

        // 6) CMS imzası
        var signed = Data()
        signed.append(data.subdata(in: 0..<start))
        signed.append(data.subdata(in: end..<data.count))
        let cms = try cmsSignature(of: signed, identity: identity)
        guard cms.count <= contentsPlaceholderBytes else { throw QPDFError.message("İmza beklenenden büyük.") }
        var hex = cms.map { String(format: "%02X", $0) }.joined()
        hex += String(repeating: "0", count: placeholderHex.count - hex.count)
        data.replaceSubrange((start + 1)..<(start + 1 + placeholderHex.count), with: Data(hex.utf8))
        return data
    }

    private static func cmsSignature(of content: Data, identity: SecIdentity) throws -> Data {
        var encoderRef: CMSEncoder?
        guard CMSEncoderCreate(&encoderRef) == errSecSuccess, let encoder = encoderRef else {
            throw QPDFError.message("CMS kodlayıcı oluşturulamadı.")
        }
        var status = CMSEncoderAddSigners(encoder, identity)
        guard status == errSecSuccess else { throw QPDFError.message("Sertifika imzalayan olarak eklenemedi (\(status)).") }
        _ = CMSEncoderSetSignerAlgorithm(encoder, kCMSEncoderDigestAlgorithmSHA256)
        _ = CMSEncoderSetHasDetachedContent(encoder, true)
        status = content.withUnsafeBytes { buf in
            CMSEncoderUpdateContent(encoder, buf.baseAddress!, content.count)
        }
        guard status == errSecSuccess else { throw QPDFError.message("İmzalanacak içerik eklenemedi (\(status)).") }
        var out: CFData?
        status = CMSEncoderCopyEncodedContent(encoder, &out)
        guard status == errSecSuccess, let result = out else {
            throw QPDFError.message("İmza oluşturulamadı. Anahtar Zinciri erişimine izin verdiğinizden emin olun (\(status)).")
        }
        return result as Data
    }

    // MARK: - Yardımcılar

    private static func pad(_ n: Int) -> String {
        let s = String(n)
        return s.count >= 10 ? s : s + String(repeating: " ", count: 10 - s.count)
    }

    private static func pdfDate(_ d: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyyMMddHHmmss"
        let tz = TimeZone.current.secondsFromGMT(for: d)
        let sign = tz >= 0 ? "+" : "-"
        let h = abs(tz) / 3600, m = (abs(tz) % 3600) / 60
        return "D:" + f.string(from: d) + String(format: "%@%02d'%02d'", sign, h, m)
    }

    /// UTF-16BE onaltılık PDF metin dizesi: <FEFF...>
    private static func pdfText(_ s: String) -> String {
        var hex = "<FEFF"
        for u in s.utf16 { hex += String(format: "%04X", u) }
        return hex + ">"
    }

    private static func lastMatch(in text: String, pattern: String) -> [String]? {
        guard let re = try? NSRegularExpression(pattern: pattern) else { return nil }
        let ns = text as NSString
        guard let m = re.matches(in: text, range: NSRange(location: 0, length: ns.length)).last else { return nil }
        return (0..<m.numberOfRanges).map { i in
            let r = m.range(at: i)
            return r.location == NSNotFound ? "" : ns.substring(with: r)
        }
    }

    private static func lastRange(in text: String, pattern: String) -> NSRange? {
        guard let re = try? NSRegularExpression(pattern: pattern) else { return nil }
        let ns = text as NSString
        return re.matches(in: text, range: NSRange(location: 0, length: ns.length)).last?.range
    }

    /// "<<" ile başlayan sözlüğün kapanış ">>" sonrasını bulur (iç içe sözlükler ve dizeler dikkate alınır).
    private static func matchingDictEnd(_ ns: NSString, from start: Int) -> Int? {
        var depth = 0
        var i = start
        var inString = 0
        while i < ns.length - 1 {
            let c = ns.character(at: i)
            if inString > 0 {
                if c == 0x5C { i += 2; continue }          // \
                if c == 0x28 { inString += 1 }              // (
                if c == 0x29 { inString -= 1 }              // )
                i += 1; continue
            }
            if c == 0x28 { inString = 1; i += 1; continue }
            let n = ns.character(at: i + 1)
            if c == 0x3C && n == 0x3C { depth += 1; i += 2; continue }   // <<
            if c == 0x3E && n == 0x3E {                                   // >>
                depth -= 1; i += 2
                if depth == 0 { return i }
                continue
            }
            i += 1
        }
        return nil
    }
}
