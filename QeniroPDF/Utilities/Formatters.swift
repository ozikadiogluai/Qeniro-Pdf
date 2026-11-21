import Foundation

extension String {
    /// Çalışma zamanında üretilen bir anahtarı (ör. enum ham değeri) String Catalog'dan çevirir.
    var loc: String { NSLocalizedString(self, comment: "") }
}

enum Fmt {
    /// Biçimlendirmede kullanılan yerel ayar: kullanıcının dil ve bölge ayarları.
    static var locale: Locale { Locale.current }

    static func fileSize(_ bytes: Int64) -> String {
        let f = ByteCountFormatter()
        f.allowedUnits = [.useKB, .useMB, .useGB]
        f.countStyle = .file
        return f.string(fromByteCount: bytes)
    }

    static func fileSize(of url: URL) -> Int64 {
        let v = try? url.resourceValues(forKeys: [.fileSizeKey])
        return Int64(v?.fileSize ?? 0)
    }

    /// "Bugün 14:20", "Dün 17:45" veya "22 Oca 2025 14:20" (dile göre: "Today 14:20", "22 Jan 2025 14:20"…)
    static func relativeDate(_ date: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(date) || cal.isDateInYesterday(date) {
            let f = DateFormatter()
            f.locale = locale
            f.dateStyle = .medium
            f.timeStyle = .short
            f.doesRelativeDateFormatting = true
            return f.string(from: date)
        }
        let full = DateFormatter()
        full.locale = locale
        full.setLocalizedDateFormatFromTemplate("dMMMyyyyjmm")
        return full.string(from: date)
    }

    /// Kısa tarih: tr "21.11.2026", en "11/21/2026", fr "21/11/2026"…
    static func shortDate(_ date: Date = Date()) -> String {
        let f = DateFormatter()
        f.locale = locale
        f.setLocalizedDateFormatFromTemplate("ddMMyyyy")
        return f.string(from: date)
    }

    static func dateTime(_ date: Date = Date()) -> String {
        let f = DateFormatter()
        f.locale = locale
        f.setLocalizedDateFormatFromTemplate("ddMMyyyyjjmm")
        return f.string(from: date)
    }

    static func percent(_ value: CGFloat) -> String {
        let f = NumberFormatter()
        f.locale = locale
        f.numberStyle = .percent
        f.maximumFractionDigits = 0
        return f.string(from: NSNumber(value: Double(value))) ?? "\(Int((value * 100).rounded()))%"
    }
}

extension Fmt {
    /// Uygulamanın şu an kullandığı arayüz dilinin kendi dilindeki adı: "Türkçe", "English", "العربية"…
    static var appLanguageName: String {
        let code = Bundle.main.preferredLocalizations.first ?? "tr"
        let loc = Locale(identifier: code)
        let name = loc.localizedString(forLanguageCode: code) ?? code
        return name.prefix(1).uppercased(with: loc) + name.dropFirst()
    }
}

extension URL {
    /// "Rapor.pdf" -> "Rapor"
    var baseName: String { deletingPathExtension().lastPathComponent }

    /// Aynı klasörde çakışmayan bir dosya adı üretir: "Rapor_sıkıştırılmış 2.pdf"
    func uniqueSibling(suffix: String, ext: String) -> URL {
        let dir = deletingLastPathComponent()
        var candidate = dir.appendingPathComponent("\(baseName)\(suffix).\(ext)")
        var n = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = dir.appendingPathComponent("\(baseName)\(suffix) \(n).\(ext)")
            n += 1
        }
        return candidate
    }
}
