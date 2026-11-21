import SwiftUI
import AppKit
import UniformTypeIdentifiers

enum ToolRunState: Equatable {
    case idle
    case running(String)
    case failed(String)
    case done(String, [URL])

    var isRunning: Bool {
        if case .running = self { return true }
        return false
    }
}

/// Araç pencerelerinin ortak iskeleti: başlık, içerik, durum, Kapat / Çalıştır düğmeleri.
struct ToolScaffold<Content: View>: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss
    let kind: ToolKind
    let runTitle: String
    let canRun: Bool
    let state: ToolRunState
    let run: () -> Void
    let content: Content

    init(kind: ToolKind, runTitle: String, canRun: Bool, state: ToolRunState,
         run: @escaping () -> Void, @ViewBuilder content: () -> Content) {
        self.kind = kind
        self.runTitle = runTitle
        self.canRun = canRun
        self.state = state
        self.run = run
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Image(systemName: kind.symbol)
                    .font(.system(size: 18))
                    .foregroundStyle(Theme.ink)
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(Theme.card2))
                VStack(alignment: .leading, spacing: 2) {
                    Text(kind.title).font(.title3.bold())
                    Text(kind.subtitle).foregroundStyle(Theme.secondaryText)
                }
            }
            Divider()
            content
            statusView
            HStack {
                Spacer()
                Button("Kapat") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                    .buttonStyle(QSecondaryButtonStyle())
                Button(runTitle, action: run)
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(QPrimaryButtonStyle())
                    .disabled(!canRun || state.isRunning)
            }
        }
        .padding(22)
        .frame(width: 620)
        .background(Theme.background)
    }

    @ViewBuilder
    private var statusView: some View {
        switch state {
        case .idle:
            EmptyView()
        case .running(let msg):
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text(msg).foregroundStyle(.secondary)
            }
        case .failed(let msg):
            Label(msg, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(Theme.red)
                .fixedSize(horizontal: false, vertical: true)
        case .done(let msg, let urls):
            VStack(alignment: .leading, spacing: 8) {
                Label(msg, systemImage: "checkmark.circle.fill")
                    .foregroundStyle(Theme.green)
                    .fixedSize(horizontal: false, vertical: true)
                HStack {
                    if urls.count == 1, let u = urls.first, u.pathExtension.lowercased() == "pdf" {
                        Button("Qeniro PDF'de Aç") {
                            app.open(u)
                            dismiss()
                        }
                    } else if urls.count == 1, let u = urls.first {
                        Button("Aç") { NSWorkspace.shared.open(u) }
                    }
                    if !urls.isEmpty {
                        Button("Finder'da Göster") { Dialogs.revealInFinder(urls) }
                    }
                }
            }
        }
    }
}

/// Sürükle-bırak destekli dosya listesi.
struct FileListEditor: View {
    @Binding var files: [URL]
    let types: [UTType]
    var multiple = true
    var reorderable = false
    var title = String(localized: "Dosyalar")

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.subheadline.bold())
            List {
                if files.isEmpty {
                    Text(multiple ? String(localized: "Dosyaları buraya sürükleyin veya \"Dosya Ekle\" ile seçin.") : String(localized: "Bir dosyayı buraya sürükleyin veya \"Dosya Seç\" ile seçin."))
                        .foregroundStyle(.secondary)
                }
                ForEach(files, id: \.self) { u in
                    HStack(spacing: 8) {
                        Image(systemName: u.pathExtension.lowercased() == "pdf" ? "doc.richtext" : "doc")
                            .foregroundStyle(Theme.pdfBadgeText)
                        Text(u.lastPathComponent).lineLimit(1)
                        Spacer()
                        Text(Fmt.fileSize(Fmt.fileSize(of: u))).font(.caption).foregroundStyle(.secondary)
                        Button {
                            files.removeAll { $0 == u }
                        } label: {
                            Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .onMove { from, to in
                    if reorderable { files.move(fromOffsets: from, toOffset: to) }
                }
            }
            .frame(height: multiple ? 170 : 56)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Theme.divider))
            HStack {
                Button(multiple ? String(localized: "Dosya Ekle…") : String(localized: "Dosya Seç…")) {
                    let picked = Dialogs.openFiles(types: types, multiple: multiple, title: multiple ? String(localized: "Dosya ekle") : String(localized: "Dosya seç"))
                    if multiple { files.append(contentsOf: picked.filter { !files.contains($0) }) }
                    else if let f = picked.first { files = [f] }
                }
                if reorderable && files.count > 1 {
                    Text("Sırayı değiştirmek için satırları sürükleyin.").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if !files.isEmpty {
                    Button("Temizle") { files.removeAll() }
                }
            }
        }
        .dropDestination(for: URL.self) { urls, _ in
            let accepted = urls.filter { accepts($0) }
            guard !accepted.isEmpty else { return false }
            if multiple { files.append(contentsOf: accepted.filter { !files.contains($0) }) } else { files = [accepted[0]] }
            return true
        }
    }

    private func accepts(_ url: URL) -> Bool {
        if types.isEmpty { return true }
        guard let t = UTType(filenameExtension: url.pathExtension) else { return false }
        return types.contains { t.conforms(to: $0) }
    }
}

enum ToolIO {
    /// Kaydedilmemiş değişiklikleri olan açık belgeyi geçici dosyaya yazar ve onu girdi olarak kullanır.
    @MainActor
    static func resolveInputs(_ req: ToolSheetRequest, app: AppState) -> [URL] {
        if let s = app.session(id: req.sessionID), s.isDirty || s.url == nil {
            let dir = FileManager.default.temporaryDirectory.appendingPathComponent("qeniro-\(UUID().uuidString)", isDirectory: true)
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let u = dir.appendingPathComponent(s.displayName)
            if let d = s.currentData(), (try? d.write(to: u)) != nil { return [u] }
        }
        return req.files
    }

    static func isTemporary(_ url: URL) -> Bool {
        url.path.hasPrefix(FileManager.default.temporaryDirectory.path) || url.path.contains("/T/qeniro-")
    }

    /// Kayıt panelinin açılacağı klasör.
    static func directory(for input: URL?) -> URL? {
        guard let input, !isTemporary(input) else { return nil }
        return input.deletingLastPathComponent()
    }

    static func sizeChange(_ before: Int64, _ after: Int64) -> String {
        let pct = before > 0 ? Int((1 - Double(after) / Double(before)) * 100) : 0
        return "\(Fmt.fileSize(before)) → \(Fmt.fileSize(after))" + (pct > 0 ? String(localized: " (%\(pct) küçüldü)") : "")
    }
}
