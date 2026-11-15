import Foundation
import AppKit

struct SavedSignature: Identifiable, Codable, Hashable {
    let id: UUID
    let fileName: String
    let created: Date
}

/// Kayıtlı imzaları ~/Library/Application Support/QeniroPDF/Signatures altında PNG olarak saklar.
@MainActor
final class SignatureStore: ObservableObject {
    static let shared = SignatureStore()

    @Published private(set) var signatures: [SavedSignature] = []
    private var cache: [UUID: NSImage] = [:]
    private let directory: URL
    private var indexURL: URL { directory.appendingPathComponent("index.json") }

    init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
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
    func add(_ image: NSImage) -> SavedSignature? {
        guard let png = Self.pngData(image) else { return nil }
        let sig = SavedSignature(id: UUID(), fileName: UUID().uuidString + ".png", created: Date())
        do {
            try png.write(to: directory.appendingPathComponent(sig.fileName), options: .atomic)
        } catch {
            return nil
        }
        signatures.insert(sig, at: 0)
        cache[sig.id] = image
        persist()
        return sig
    }

    func image(for id: UUID) -> NSImage? {
        if let img = cache[id] { return img }
        guard let sig = signatures.first(where: { $0.id == id }),
              let img = NSImage(contentsOf: directory.appendingPathComponent(sig.fileName)) else { return nil }
        cache[id] = img
        return img
    }

    func delete(_ id: UUID) {
        guard let i = signatures.firstIndex(where: { $0.id == id }) else { return }
        let sig = signatures.remove(at: i)
        // Silme yerine dosyanın üzerine boş veri yazılmaz; doğrudan kaldırılır.
        try? FileManager.default.removeItem(at: directory.appendingPathComponent(sig.fileName))
        cache[id] = nil
        persist()
    }

    static func pngData(_ image: NSImage) -> Data? {
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .png, properties: [:])
    }
}
