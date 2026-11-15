import SwiftUI
import AppKit

struct HomeView: View {
    @EnvironmentObject var app: AppState
    let columns = Array(repeating: GridItem(.flexible(), spacing: 14), count: 4)

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("Hoş Geldiniz")
                    .font(Theme.titleFont)
                Text("Qeniro PDF'lerinizle daha fazlasını yapın.")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
                    .padding(.bottom, 20)

                LazyVGrid(columns: columns, spacing: 14) {
                    ForEach(ToolKind.homeTools) { tool in
                        ToolCard(tool: tool)
                    }
                }

                RecentFilesSection(limit: 6)
                    .padding(.top, 26)
            }
            .padding(.horizontal, 28)
            .padding(.top, 24)
            .padding(.bottom, 28)
            .frame(maxWidth: 1100, alignment: .leading)
        }
    }
}

/// Ana sayfadaki büyük araç kartı (simge, başlık, açıklama).
struct ToolCard: View {
    @EnvironmentObject var app: AppState
    let tool: ToolKind
    @State private var hover = false

    var body: some View {
        Button {
            app.perform(tool)
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                Image(systemName: tool.symbol)
                    .font(.system(size: 22, weight: .regular))
                    .foregroundStyle(tool.tint)
                    .frame(height: 28)
                Text(tool.title)
                    .font(Theme.cardTitleFont)
                    .foregroundStyle(.primary)
                Text(tool.subtitle)
                    .font(Theme.captionFont)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 112, alignment: .topLeading)
            .qCard(hover: hover)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .help(tool.subtitle)
    }
}

/// Tüm Araçlar sayfasındaki küçük döşeme.
struct ToolTile: View {
    @EnvironmentObject var app: AppState
    let tool: ToolKind
    @State private var hover = false

    var body: some View {
        Button {
            app.perform(tool)
        } label: {
            VStack(spacing: 8) {
                Image(systemName: tool.symbol)
                    .font(.system(size: 22))
                    .foregroundStyle(tool.tint)
                Text(tool.title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }
            .padding(10)
            .frame(maxWidth: .infinity, minHeight: 88)
            .qCard(hover: hover)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .help(tool.subtitle)
    }
}

struct AllToolsView: View {
    let columns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 5)

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("Tüm Araçlar")
                    .font(Theme.titleFont)
                    .padding(.bottom, 8)
                ForEach(ToolGroup.allCases) { group in
                    Text(group.rawValue)
                        .font(Theme.sectionFont)
                        .padding(.top, 18)
                        .padding(.bottom, 10)
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(group.tools) { ToolTile(tool: $0) }
                    }
                }
            }
            .padding(.horizontal, 28)
            .padding(.top, 24)
            .padding(.bottom, 28)
            .frame(maxWidth: 1100, alignment: .leading)
        }
    }
}

// MARK: - Son dosyalar

struct RecentFilesSection: View {
    @EnvironmentObject var app: AppState
    @EnvironmentObject var library: FileLibrary
    let limit: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Son Dosyalar").font(.system(size: 15, weight: .semibold))
                Spacer()
                Button { app.showShell(.recent) } label: { Image(systemName: "arrow.up.left.and.arrow.down.right") }
                    .buttonStyle(.plain).help("Tümünü göster")
                Button { library.clearRecents() } label: { Image(systemName: "xmark") }
                    .buttonStyle(.plain).help("Listeyi temizle")
                    .disabled(library.recents.isEmpty)
            }
            .foregroundStyle(.secondary)
            if library.recents.isEmpty {
                Text("Henüz açılmış bir dosya yok. Bir PDF'yi bu pencereye sürükleyin veya soldaki \"PDF Aç\" düğmesini kullanın.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 12)
            } else {
                VStack(spacing: 0) {
                    ForEach(library.recents.prefix(limit)) { e in
                        FileRow(entry: e)
                        Divider()
                    }
                }
            }
        }
    }
}

struct FileRow: View {
    @EnvironmentObject var app: AppState
    @EnvironmentObject var library: FileLibrary
    let entry: FileEntry
    @State private var hover = false

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "doc.richtext")
                .font(.system(size: 18))
                .foregroundStyle(Theme.accent)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.name)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                Text("\(Fmt.fileSize(entry.size)) · \(Fmt.relativeDate(entry.date))")
                    .font(Theme.captionFont)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if library.isStarred(entry.url) {
                Image(systemName: "star.fill").foregroundStyle(.yellow).font(.caption)
            }
            if !entry.exists {
                Text("Bulunamadı").font(.caption).foregroundStyle(.secondary)
            }
            Menu {
                Button("Aç") { open() }
                Button(library.isStarred(entry.url) ? "Yıldızı Kaldır" : "Yıldızla") { library.toggleStar(entry.resolvedURL()) }
                Button("Finder'da Göster") { Dialogs.revealInFinder([entry.resolvedURL()]) }
                Divider()
                Button("Listeden Kaldır") { library.removeRecent(entry) }
            } label: {
                Image(systemName: "ellipsis")
                    .rotationEffect(.degrees(90))
                    .frame(width: 24, height: 24)
            }
            .menuStyle(.button)
            .buttonStyle(.borderless)
            .menuIndicator(.hidden)
            .frame(width: 28)
        }
        .padding(.vertical, 7)
        .padding(.horizontal, 6)
        .background(RoundedRectangle(cornerRadius: 6).fill(hover ? Theme.activeNav.opacity(0.5) : Color.clear))
        .contentShape(Rectangle())
        .onHover { hover = $0 }
        .onTapGesture { open() }
    }

    private func open() {
        let url = entry.resolvedURL()
        guard FileManager.default.fileExists(atPath: url.path) else {
            Dialogs.info("Dosya bulunamadı", "\"\(entry.name)\" taşınmış veya silinmiş olabilir.")
            return
        }
        app.open(url)
    }
}

enum FileListKind { case recent, starred }

struct FileListPage: View {
    @EnvironmentObject var library: FileLibrary
    let kind: FileListKind
    @State private var query = ""

    private var entries: [FileEntry] {
        let all = kind == .recent ? library.recents : library.starred
        guard !query.isEmpty else { return all }
        return all.filter { $0.name.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(kind == .recent ? "Son Dosyalar" : "Yıldızlı")
                .font(Theme.titleFont)
            TextField("Dosya adında ara", text: $query)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 320)
            if entries.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: kind == .recent ? "clock" : "star")
                        .font(.system(size: 34)).foregroundStyle(.secondary)
                    Text(kind == .recent ? "Son açılan dosya yok." : "Yıldızlı dosya yok. Bir dosyayı yıldızlamak için görüntüleyicideki yıldız düğmesini veya listedeki ⋮ menüsünü kullanın.")
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 380)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 60)
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(entries) { e in
                            FileRow(entry: e)
                            Divider()
                        }
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 28)
        .padding(.top, 24)
        .frame(maxWidth: 1100, alignment: .leading)
    }
}
