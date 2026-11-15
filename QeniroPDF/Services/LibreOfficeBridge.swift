import Foundation

/// Kuruluysa LibreOffice'i arka planda (--headless) kullanarak daha yüksek sadakatli dönüştürme yapar.
enum LibreOfficeBridge {
    static let candidatePaths = [
        "/Applications/LibreOffice.app/Contents/MacOS/soffice",
        NSHomeDirectory() + "/Applications/LibreOffice.app/Contents/MacOS/soffice"
    ]

    static var executable: String? {
        candidatePaths.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    static var isAvailable: Bool { executable != nil }

    /// `input` dosyasını `format` (pdf, docx…) biçimine çevirir; çıktı geçici klasöre yazılır.
    static func convert(_ input: URL, to format: String, inputFilter: String? = nil) throws -> URL {
        guard let exe = executable else { throw QPDFError.message("LibreOffice bulunamadı.") }
        let outDir = FileManager.default.temporaryDirectory.appendingPathComponent("qeniro-lo-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
        let p = Process()
        p.executableURL = URL(fileURLWithPath: exe)
        var args = ["--headless", "--norestore", "--nologo"]
        if let inputFilter { args.append("--infilter=\(inputFilter)") }
        args += ["--convert-to", format, "--outdir", outDir.path, input.path]
        p.arguments = args
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe
        try p.run()
        p.waitUntilExit()
        let target = outDir.appendingPathComponent(input.deletingPathExtension().lastPathComponent)
            .appendingPathExtension(format.components(separatedBy: ":").first ?? format)
        guard p.terminationStatus == 0, FileManager.default.fileExists(atPath: target.path) else {
            let log = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            throw QPDFError.message("LibreOffice dönüştürmesi başarısız oldu. \(log.prefix(300))")
        }
        return target
    }
}
