import Foundation

enum Fmt {
    static let trLocale = Locale(identifier: "tr_TR")

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

    /// "Bugün 14:20", "Dün 17:45" veya "22 Oca 2025 10:11"
    static func relativeDate(_ date: Date) -> String {
        let cal = Calendar.current
        let time = DateFormatter()
        time.locale = trLocale
        time.dateFormat = "HH:mm"
        if cal.isDateInToday(date) { return "Bugün " + time.string(from: date) }
        if cal.isDateInYesterday(date) { return "Dün " + time.string(from: date) }
        let full = DateFormatter()
        full.locale = trLocale
        full.dateFormat = "d MMM yyyy HH:mm"
        return full.string(from: date)
    }

    static func shortDate(_ date: Date = Date()) -> String {
        let f = DateFormatter()
        f.locale = trLocale
        f.dateFormat = "dd.MM.yyyy"
        return f.string(from: date)
    }

    static func dateTime(_ date: Date = Date()) -> String {
        let f = DateFormatter()
        f.locale = trLocale
        f.dateFormat = "dd.MM.yyyy HH:mm"
        return f.string(from: date)
    }

    static func percent(_ value: CGFloat) -> String {
        "\(Int((value * 100).rounded()))%"
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
