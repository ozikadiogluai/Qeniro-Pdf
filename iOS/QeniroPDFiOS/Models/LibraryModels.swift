import Foundation
import UIKit
import SwiftUI

// MARK: - Son dosyalar / Yıldızlı

/// Son dosyalar ve yıldızlı dosyalar listesindeki bir kayıt. Dosyalar uygulamasından gelen
/// dosyalar için yer imi (bookmark) saklanır; iOS'ta yer imi güvenlik kapsamını da taşır.
struct FileEntry: Codable, Identifiable, Hashable {
    var id: String { path }
    var path: String
    var name: String
    var size: Int64
    var date: Date
    var bookmark: Data?

    init(url: URL) {
        path = url.path
        name = url.lastPathComponent
        let values = try? url.resourceValues(forKeys: [.fileSizeKey])
        size = Int64(values?.fileSize ?? 0)
        date = Date()
        bookmark = try? url.bookmarkData(options: .minimalBookmark, includingResourceValuesForKeys: nil, relativeTo: nil)
    }

    /// Dosya taşınmış olsa bile yer imini çözerek güncel URL'yi döndürür.
    func resolvedURL() -> URL {
        if let bookmark {
            var stale = false
            if let u = try? URL(resolvingBookmarkData: bookmark, options: [], relativeTo: nil, bookmarkDataIsStale: &stale) {
                return u
            }
        }
        return URL(fileURLWithPath: path)
    }
}

/// Son Dosyalar + Yıldızlı listelerini UserDefaults'ta saklar.
@MainActor
final class FileLibrary: ObservableObject {
    @Published private(set) var recents: [FileEntry] = []
    @Published private(set) var starred: [FileEntry] = []

    private let recentsKey = "qeniro.ios.recents"
    private let starredKey = "qeniro.ios.starred"
    private let maxRecents = 40

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

    func isStarred(_ entry: FileEntry) -> Bool { starred.contains { $0.path == entry.path } }

    func toggleStar(_ url: URL) {
        if let i = starred.firstIndex(where: { $0.path == url.path }) {
            starred.remove(at: i)
        } else {
            let ok = url.startAccessingSecurityScopedResource()
            starred.insert(FileEntry(url: url), at: 0)
            if ok { url.stopAccessingSecurityScopedResource() }
        }
        persist()
    }

    func toggleStar(_ entry: FileEntry) {
        if let i = starred.firstIndex(where: { $0.path == entry.path }) {
            starred.remove(at: i)
        } else {
            var e = entry; e.date = Date()
            starred.insert(e, at: 0)
        }
        persist()
    }
}

// MARK: - Kayıtlı imzalar

struct SavedSignature: Identifiable, Codable, Hashable {
    let id: UUID
    let fileName: String
    let created: Date
    var isInitials: Bool? = false
}

/// Kayıtlı imzaları uygulamanın Application Support/Signatures klasöründe PNG olarak saklar
/// (Dosyalar uygulamasında görünmez, yalnızca uygulama içinde kalır).
@MainActor
final class SignatureStore: ObservableObject {
    static let shared = SignatureStore()

    @Published private(set) var signatures: [SavedSignature] = []
    private var cache: [UUID: UIImage] = [:]
    private let directory: URL
    private var indexURL: URL { directory.appendingPathComponent("index.json") }

    init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        directory = base.appendingPathComponent("QeniroPDF/Signatures", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if let data = try? Data(contentsOf: indexURL),
           let list = try? JSONDecoder().decode([SavedSignature].self, from: data) {
            signatures = list.filter { FileManager.default.fileExists(atPath: directory.appendingPathComponent($0.fileName).path) }
        }
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(signatures) {
            try? data.write(to: indexURL, options: .atomic)
        }
    }

    @discardableResult
    func add(_ image: UIImage, initials: Bool = false) -> SavedSignature? {
        guard let png = image.pngData() else { return nil }
        let sig = SavedSignature(id: UUID(), fileName: UUID().uuidString + ".png", created: Date(), isInitials: initials)
        do {
            try png.write(to: directory.appendingPathComponent(sig.fileName), options: [.atomic, .completeFileProtection])
        } catch {
            return nil
        }
        signatures.insert(sig, at: 0)
        cache[sig.id] = image
        persist()
        return sig
    }

    func image(for id: UUID) -> UIImage? {
        if let img = cache[id] { return img }
        guard let sig = signatures.first(where: { $0.id == id }),
              let img = UIImage(contentsOfFile: directory.appendingPathComponent(sig.fileName).path) else { return nil }
        cache[id] = img
        return img
    }

    func delete(_ id: UUID) {
        guard let i = signatures.firstIndex(where: { $0.id == id }) else { return }
        let sig = signatures.remove(at: i)
        try? FileManager.default.removeItem(at: directory.appendingPathComponent(sig.fileName))
        cache[id] = nil
        persist()
    }
}

// MARK: - Metin biçimi

/// Düzenle panelindeki metin biçimi.
struct TextStyle: Equatable {
    var family: String = "Arial"
    var size: CGFloat = 12
    var bold = false
    var italic = false
    var underline = false
    var color: Color = .black

    static let families = ["Arial", "Helvetica", "Helvetica Neue", "Times New Roman", "Georgia", "Verdana",
                           "Trebuchet MS", "Courier New", "Menlo", "Avenir Next", "Gill Sans"]
    static let sizes: [CGFloat] = [6, 7, 8, 9, 10, 11, 12, 14, 16, 18, 20, 24, 28, 32, 36, 48, 60, 72]

    var uiColor: UIColor { UIColor(color) }

    func makeFont(scale: CGFloat = 1) -> UIFont {
        let pt = max(1, size * scale)
        var traits: UIFontDescriptor.SymbolicTraits = []
        if bold { traits.insert(.traitBold) }
        if italic { traits.insert(.traitItalic) }
        let base = UIFontDescriptor(fontAttributes: [.family: family])
        if let d = base.withSymbolicTraits(traits) { return UIFont(descriptor: d, size: pt) }
        return UIFont(descriptor: base, size: pt)
    }
}
