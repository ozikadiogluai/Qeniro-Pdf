import Foundation

/// iCloud Drive ve ~/Library/CloudStorage altındaki (Google Drive, Dropbox, OneDrive…) PDF'leri listeler.
struct CloudLocation: Identifiable, Hashable, Sendable {
    var id: String { url.path }
    let name: String
    let url: URL
}

struct CloudFile: Identifiable, Hashable, Sendable {
    var id: String { url.path }
    let url: URL
    let size: Int64
    let modified: Date
    let location: String
}

enum CloudStore {
    static func locations() -> [CloudLocation] {
        var out: [CloudLocation] = []
        let home = URL(fileURLWithPath: NSHomeDirectory())
        let icloud = home.appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs", isDirectory: true)
        if FileManager.default.fileExists(atPath: icloud.path) {
            out.append(CloudLocation(name: "iCloud Drive", url: icloud))
        }
        let storage = home.appendingPathComponent("Library/CloudStorage", isDirectory: true)
        if let items = try? FileManager.default.contentsOfDirectory(at: storage, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) {
            for u in items.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
                let raw = u.lastPathComponent
                let pretty = raw.replacingOccurrences(of: "GoogleDrive-", with: "Google Drive · ")
                    .replacingOccurrences(of: "OneDrive-", with: "OneDrive · ")
                    .replacingOccurrences(of: "Dropbox", with: "Dropbox")
                out.append(CloudLocation(name: pretty, url: u))
            }
        }
        return out
    }

    /// Konumdaki PDF'leri (en fazla `limit`, en yeni önce) bulur. Arka planda çağrılmalıdır.
    static func pdfs(in location: CloudLocation, limit: Int = 300, maxDepth: Int = 4) -> [CloudFile] {
        let keys: [URLResourceKey] = [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey]
        guard let en = FileManager.default.enumerator(at: location.url, includingPropertiesForKeys: keys,
                                                      options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { return [] }
        var files: [CloudFile] = []
        let baseDepth = location.url.pathComponents.count
        while let u = en.nextObject() as? URL {
            if u.pathComponents.count - baseDepth > maxDepth { en.skipDescendants(); continue }
            guard u.pathExtension.lowercased() == "pdf" else { continue }
            let v = try? u.resourceValues(forKeys: Set(keys))
            guard v?.isRegularFile == true else { continue }
            files.append(CloudFile(url: u, size: Int64(v?.fileSize ?? 0), modified: v?.contentModificationDate ?? .distantPast, location: location.name))
            if files.count >= limit * 3 { break }
        }
        return Array(files.sorted { $0.modified > $1.modified }.prefix(limit))
    }
}
