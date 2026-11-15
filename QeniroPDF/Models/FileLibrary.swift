import Foundation
import AppKit

/// Son dosyalar ve yıldızlı dosyalar listesindeki bir kayıt.
struct FileEntry: Codable, Identifiable, Hashable {
    var id: String { path }
    var path: String
    var name: String
    var size: Int64
    var date: Date
    var bookmark: Data?

    var url: URL { URL(fileURLWithPath: path) }

    init(url: URL) {
        path = url.path
        name = url.lastPathComponent
        let values = try? url.resourceValues(forKeys: [.fileSizeKey])
        size = Int64(values?.fileSize ?? 0)
        date = Date()
        bookmark = try? url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
    }

    /// Dosya taşınmış olsa bile yer imini çözerek güncel URL'yi döndürür.
    func resolvedURL() -> URL {
        if let bookmark {
            var stale = false
            if let u = try? URL(resolvingBookmarkData: bookmark, options: [], relativeTo: nil, bookmarkDataIsStale: &stale) {
                return u
            }
        }
        return url
    }

    var exists: Bool { FileManager.default.fileExists(atPath: resolvedURL().path) }
}

/// Son Dosyalar + Yıldızlı listelerini UserDefaults'ta saklar.
@MainActor
final class FileLibrary: ObservableObject {
    @Published private(set) var recents: [FileEntry] = []
    @Published private(set) var starred: [FileEntry] = []

    private let recentsKey = "qeniro.recents"
    private let starredKey = "qeniro.starred"
    private let maxRecents = 30

    init() {
        recents = load(recentsKey)
        starred = load(starredKey)
    }

    private func load(_ key: String) -> [FileEntry] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let list = try? JSONDecoder().decode([FileEntry].self, from: data) else { return [] }
        return list
    }

    private func persist() {
        if let d = try? JSONEncoder().encode(recents) { UserDefaults.standard.set(d, forKey: recentsKey) }
        if let d = try? JSONEncoder().encode(starred) { UserDefaults.standard.set(d, forKey: starredKey) }
    }

    func noteOpened(_ url: URL) {
        recents.removeAll { $0.path == url.path }
        recents.insert(FileEntry(url: url), at: 0)
        if recents.count > maxRecents { recents = Array(recents.prefix(maxRecents)) }
        if let i = starred.firstIndex(where: { $0.path == url.path }) {
            var e = FileEntry(url: url); e.date = starred[i].date
            starred[i] = e
        }
        persist()
    }

    func removeRecent(_ entry: FileEntry) {
        recents.removeAll { $0.path == entry.path }
        persist()
    }

    func clearRecents() {
        recents.removeAll()
        persist()
    }

    func isStarred(_ url: URL?) -> Bool {
        guard let url else { return false }
        return starred.contains { $0.path == url.path }
    }

    func toggleStar(_ url: URL) {
        if let i = starred.firstIndex(where: { $0.path == url.path }) {
            starred.remove(at: i)
        } else {
            starred.insert(FileEntry(url: url), at: 0)
        }
        persist()
    }
}

/// Uygulama içi bildirim (zil simgesi altında listelenir).
struct AppNotice: Identifiable {
    let id = UUID()
    let date = Date()
    let message: String
    let urls: [URL]
}
