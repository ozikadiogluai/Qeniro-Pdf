import Foundation
import Security

/// Belgedeki bir dijital imzanın doğrulama sonucu.
struct PDFSignatureInfo: Identifiable {
    enum Status: Equatable {
        case valid, invalid, unknown
    }

    let id: Int
    var signer: String
    var reason: String
    var time: String
    var subFilter: String
    var status: Status
    var detail: String
}

/// PDF imzalarını PDFium ile okur ve CMS imzasını Security çerçevesiyle doğrular.
enum SignatureVerifier {
    /// `fileData` diskteki dosyanın baytları olmalıdır (ByteRange dosya baytlarına göredir).
    @MainActor
    static func verify(fileData: Data, password: String?) -> [PDFSignatureInfo] {
        guard let editor = try? PDFiumEditor(data: fileData, password: password) else { return [] }
        var out: [PDFSignatureInfo] = []
        for (i, sig) in editor.signatures().enumerated() {
            out.append(check(sig, index: i, file: fileData))
        }
        return out
    }

    private static func check(_ sig: PDFRawSignature, index: Int, file: Data) -> PDFSignatureInfo {
        var info = PDFSignatureInfo(id: index, signer: "", reason: sig.reason, time: formatTime(sig.time),
                                    subFilter: sig.subFilter, status: .unknown, detail: "")
        let der = trimDER(sig.contents)
        guard !der.isEmpty else {
            info.detail = "İmza verisi boş; imza alanı imzalanmamış olabilir."
            return info
        }
        guard sig.byteRange.count >= 2, sig.byteRange.count % 2 == 0 else {
            info.status = .invalid
            info.detail = "İmzanın bayt aralığı (ByteRange) eksik."
            return info
        }
        var signed = Data()
        var k = 0
        while k + 1 < sig.byteRange.count {
            let start = sig.byteRange[k], length = sig.byteRange[k + 1]
            guard start >= 0, length >= 0, start + length <= file.count else {
                info.status = .invalid
                info.detail = "İmzanın kapsadığı bayt aralığı dosyayla uyuşmuyor; dosya imzadan sonra değiştirilmiş olabilir."
                return info
            }
            signed.append(file.subdata(in: start..<(start + length)))
            k += 2
        }

        var decoderRef: CMSDecoder?
        guard CMSDecoderCreate(&decoderRef) == errSecSuccess, let decoder = decoderRef else {
            info.detail = "İmza çözücüsü oluşturulamadı."
            return info
        }
        var status: OSStatus = der.withUnsafeBytes { buf -> OSStatus in
            guard let base = buf.baseAddress else { return errSecParam }
            return CMSDecoderUpdateMessage(decoder, base, der.count)
        }
        if status == errSecSuccess { status = CMSDecoderSetDetachedContent(decoder, signed as CFData) }
        if status == errSecSuccess { status = CMSDecoderFinalizeMessage(decoder) }
        guard status == errSecSuccess else {
            info.detail = "İmza biçimi okunamadı (\(sig.subFilter.isEmpty ? "bilinmeyen" : sig.subFilter)). Bu imza türü uygulamada doğrulanamıyor."
            return info
        }
        var signerCount = 0
        _ = CMSDecoderGetNumSigners(decoder, &signerCount)
        guard signerCount > 0 else {
            info.status = .invalid
            info.detail = "İmzada imzalayan bilgisi yok."
            return info
        }
        var signerStatus: CMSSignerStatus = .unsigned
        var certResult: OSStatus = errSecSuccess
        let policy = SecPolicyCreateBasicX509()
        _ = CMSDecoderCopySignerStatus(decoder, 0, policy, true, &signerStatus, nil, &certResult)
        var cert: SecCertificate?
        if CMSDecoderCopySignerCert(decoder, 0, &cert) == errSecSuccess, let cert {
            info.signer = (SecCertificateCopySubjectSummary(cert) as String?) ?? ""
        }
        switch signerStatus {
        case .valid:
            info.status = .valid
            info.detail = "İmza geçerli; belge imzalandıktan sonra değiştirilmemiş ve sertifika güvenilir."
        case .invalidSignature:
            info.status = .invalid
            info.detail = "İmza geçersiz: belge imzalandıktan sonra değiştirilmiş."
        case .invalidCert:
            info.status = .invalid
            info.detail = "Belge değiştirilmemiş, ancak imzalayanın sertifikası doğrulanamadı (güvenilir bir kökten değil, süresi dolmuş veya iptal edilmiş olabilir)."
        case .needsDetachedContent:
            info.detail = "İmzalanan içerik bulunamadı."
        default:
            info.detail = "İmza durumu belirlenemedi."
        }
        return info
    }

    /// /Contents onaltılık alanı sıfırlarla doldurulur; yalnızca DER yapısının kendisini al.
    private static func trimDER(_ data: Data) -> Data {
        let b = [UInt8](data)
        guard b.count > 2, b[0] == 0x30 else { return data }
        let first = Int(b[1])
        let total: Int
        if first < 0x80 {
            total = 2 + first
        } else if first == 0x80 {
            return data
        } else {
            let n = first & 0x7F
            guard n <= 4, b.count > 2 + n else { return data }
            var len = 0
            for i in 0..<n { len = (len << 8) | Int(b[2 + i]) }
            total = 2 + n + len
        }
        guard total > 0, total <= b.count else { return data }
        return Data(b[0..<total])
    }

    /// "D:20240115103000+03'00'" -> "15.01.2024 10:30"
    private static func formatTime(_ s: String) -> String {
        var t = s
        if t.hasPrefix("D:") { t.removeFirst(2) }
        let digits = Array(t.prefix(14))
        guard digits.count >= 12, digits.allSatisfy({ $0.isNumber }) else { return s }
        let str = String(digits)
        func part(_ a: Int, _ len: Int) -> String {
            let start = str.index(str.startIndex, offsetBy: a)
            return String(str[start..<str.index(start, offsetBy: len)])
        }
        return "\(part(6, 2)).\(part(4, 2)).\(part(0, 4)) \(part(8, 2)):\(part(10, 2))"
    }
}
