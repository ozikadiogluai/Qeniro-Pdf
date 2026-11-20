import SwiftUI
import AppKit

/// Ana Sayfa: lacivert kahraman kart (karşılama, arama, PDF Aç, 8 araç dairesi),
/// altta Son Dosyalar tablosu ve Diğer araçlar kartı.
struct HomeView: View {
    @EnvironmentObject var app: AppState
    @EnvironmentObject var library: FileLibrary
    @State private var query = ""

    private let toolColumns = Array(repeating: GridItem(.flexible(minimum: 0), spacing: 8), count: 8)

    private var firstName: String {
        let full = NSFullUserName().isEmpty ? NSUserName() : NSFullUserName()
        return full.split(separator: " ").first.map(String.init) ?? full
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                hero
                if query.trimmingCharacters(in: .whitespaces).isEmpty {
                    HStack(alignment: .top, spacing: 10) {
                        RecentFilesSection(limit: 6)
                            .frame(maxWidth: .infinity)
                            .layoutPriority(1.5)
                        otherTools
                            .frame(width: 300)
                    }
                } else {
                    searchResults
                }
            }
            .frame(maxWidth: 1240, alignment: .leading)
        }
    }

    // MARK: Kahraman

    private var hero: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Hoş geldin, \(firstName)")
                        .font(.largeTitle.weight(.bold))
                        .foregroundStyle(Color.white)
                    Text("PDF'lerinle daha fazlasını yap.")
                        .font(.body)
                        .foregroundStyle(Color.white.opacity(0.75))
                }
                Spacer(minLength: 12)
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 13, weight: .medium))
                        .accessibilityHidden(true)
                    TextField("", text: $query, prompt: Text("Dosya veya araç ara").foregroundStyle(Color.white.opacity(0.78)))
                        .textFieldStyle(.plain)
                        .foregroundStyle(Color.white)
                        .accessibilityLabel("Dosya veya araç ara")
                    if !query.isEmpty {
                        Button { query = "" } label: { Image(systemName: "xmark.circle.fill") }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Aramayı temizle")
                    }
                }
                .foregroundStyle(Color.white.opacity(0.78))
                .padding(.horizontal, 14)
                .frame(width: 300, height: 38)
                .background(Capsule().fill(Color.white.opacity(0.10)))
                Button { app.openPanel() } label: {
                    Label("PDF Aç", systemImage: "plus")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Theme.hexColor(0x121A21))
                        .padding(.horizontal, 18)
                        .frame(height: 38)
                        .background(Capsule().fill(Color.white))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .help("PDF aç (⌘O)")
            }

            LazyVGrid(columns: toolColumns, spacing: 8) {
                ForEach(ToolKind.homeTools) { tool in
                    HeroToolButton(tool: tool)
                }
            }
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 26)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(Theme.heroGradient()))
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    // MARK: Diğer araçlar

    private var otherTools: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Diğer araçlar")
                .font(.title3.weight(.semibold))
                .foregroundStyle(Theme.text)
                .padding(.bottom, 4)
            OtherToolRow(symbol: "doc.text.viewfinder", title: "Tara ve OCR uygula") {
                withDocument { $0.runOCR(force: false) }
            }
            OtherToolRow(symbol: "eye.slash", title: "PDF'de sansürle") { app.perform(.redact) }
            OtherToolRow(symbol: "list.bullet.rectangle", title: "Form hazırla") {
                withDocument { s in
                    s.showOrganizer = false
                    s.panel = .formPrepare
                }
            }
            OtherToolRow(symbol: "checkmark.seal", title: "Sertifikayla imzala") { app.perform(.certificateSign) }
            OtherToolRow(symbol: "trash.slash", title: "Hassas bilgileri kaldır") { app.perform(.sanitize) }
            OtherToolRow(symbol: "square.grid.2x2", title: "Tüm araçlar") { app.showShell(.tools) }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .qCard(radius: Theme.cardRadius)
    }

    private func withDocument(_ configure: (DocumentSession) -> Void) {
        if let s = app.activeSession { configure(s); return }
        guard let url = Dialogs.openPDFs(title: "Bir PDF seçin").first, let s = app.open(url) else { return }
        configure(s)
    }

    // MARK: Arama

    private var matchingTools: [ToolKind] {
        let q = query.trimmingCharacters(in: .whitespaces)
        return ToolKind.allCases.filter { $0.title.localizedCaseInsensitiveContains(q) || $0.subtitle.localizedCaseInsensitiveContains(q) }
    }

    private var matchingFiles: [FileEntry] {
        let q = query.trimmingCharacters(in: .whitespaces)
        return (library.recents + library.starred.filter { s in !library.recents.contains { $0.url == s.url } })
            .filter { $0.name.localizedCaseInsensitiveContains(q) }
    }

    private var searchResults: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Dosyalar").font(.title3.weight(.semibold)).foregroundStyle(Theme.text).padding(.bottom, 4)
                if matchingFiles.isEmpty {
                    Text("Eşleşen dosya yok.").font(.callout).foregroundStyle(Theme.secondaryText).padding(.vertical, 8)
                } else {
                    FileTableHeader()
                    ForEach(matchingFiles) { e in
                        FileRow(entry: e)
                        Rectangle().fill(Theme.divider).frame(height: 1)
                    }
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .qCard(radius: Theme.cardRadius)

            VStack(alignment: .leading, spacing: 4) {
                Text("Araçlar").font(.title3.weight(.semibold)).foregroundStyle(Theme.text).padding(.bottom, 4)
                if matchingTools.isEmpty {
                    Text("Eşleşen araç yok.").font(.callout).foregroundStyle(Theme.secondaryText).padding(.vertical, 8)
                }
                ForEach(matchingTools) { t in
                    OtherToolRow(symbol: t.symbol, title: t.title) { app.perform(t) }
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 16)
            .frame(width: 300, alignment: .leading)
            .qCard(radius: Theme.cardRadius)
        }
    }
}

extension Theme {
    /// Sabit (açık/koyu değişmeyen) renk; kahraman alanındaki beyaz düğme yazısı gibi.
    static func hexColor(_ value: UInt32) -> Color { Color(nsColor: hex(value)) }
}

/// Kahraman alanındaki 54 pt daire araç düğmesi.
struct HeroToolButton: View {
    @EnvironmentObject var app: AppState
    let tool: ToolKind
    @State private var hover = false

    var body: some View {
        Button {
            app.perform(tool)
        } label: {
            VStack(spacing: 8) {
                Image(systemName: tool.symbol)
                    .font(.system(size: 20, weight: .regular))
                    .foregroundStyle(Color.white)
                    .frame(width: 54, height: 54)
                    .background(Circle().fill(Color.white.opacity(hover ? 0.18 : 0.12)))
                Text(tool.shortTitle)
                    .font(.callout)
                    .foregroundStyle(Color.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .help(tool.subtitle)
        .accessibilityLabel(tool.title)
    }
}

/// Kart içindeki "simge dairesi + başlık" satırı.
struct OtherToolRow: View {
    let symbol: String
    let title: String
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: symbol)
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.ink)
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(Theme.card2))
                Text(title)
                    .font(.body)
                    .foregroundStyle(Theme.text)
                Spacer(minLength: 0)
            }
            .padding(.vertical, 3)
            .padding(.horizontal, 4)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(hover ? Theme.card2.opacity(0.6) : Color.clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }
}

/// Tüm Araçlar sayfasındaki döşeme: kart2 daire içinde koyu simge + ad.
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
                    .font(.system(size: 19))
                    .foregroundStyle(Theme.ink)
                    .frame(width: 50, height: 50)
                    .background(Circle().fill(Theme.card2))
                Text(tool.title)
                    .font(.callout)
                    .foregroundStyle(Theme.text)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }
            .padding(10)
            .frame(maxWidth: .infinity, minHeight: 104)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(hover ? Theme.card2.opacity(0.6) : Color.clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .help(tool.subtitle)
    }
}

struct AllToolsView: View {
    let columns = Array(repeating: GridItem(.flexible(minimum: 0), spacing: 8), count: 5)

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Text("Tüm Araçlar")
                    .font(Theme.titleFont)
                    .foregroundStyle(Theme.text)
                    .padding(.horizontal, 6)
                    .padding(.top, 8)
                    .padding(.bottom, 4)
                ForEach(ToolGroup.allCases) { group in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(group.rawValue)
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(Theme.text)
                        LazyVGrid(columns: columns, spacing: 6) {
                            ForEach(group.tools) { ToolTile(tool: $0) }
                        }
                    }
                    .padding(.horizontal, 18)
                    .padding(.vertical, 16)
                    .qCard(radius: Theme.cardRadius)
                }
            }
            .frame(maxWidth: 1240, alignment: .leading)
        }
    }
}

// MARK: - Son dosyalar

struct RecentFilesSection: View {
    @EnvironmentObject var app: AppState
    @EnvironmentObject var library: FileLibrary
    let limit: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Son Dosyalar")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Theme.text)
                Spacer()
                Button("Tümünü gör") { app.showShell(.recent) }
                    .buttonStyle(.plain)
                    .font(.callout)
                    .foregroundStyle(Theme.secondaryText)
                Button { library.clearRecents() } label: { Image(systemName: "xmark") }
                    .buttonStyle(.plain)
                    .foregroundStyle(Theme.secondaryText)
                    .help("Listeyi temizle")
                    .accessibilityLabel("Listeyi temizle")
                    .disabled(library.recents.isEmpty)
            }
            .padding(.bottom, 8)
            if library.recents.isEmpty {
                Text("Henüz açılmış bir dosya yok. Bir PDF'yi bu pencereye sürükleyin veya yukarıdaki \"PDF Aç\" düğmesini kullanın.")
                    .font(.callout)
                    .foregroundStyle(Theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.vertical, 12)
            } else {
                FileTableHeader()
                let items = Array(library.recents.prefix(limit))
                ForEach(Array(items.enumerated()), id: \.element.id) { i, e in
                    FileRow(entry: e)
                    if i < items.count - 1 {
                        Rectangle().fill(Theme.divider).frame(height: 1)
                    }
                }
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .qCard(radius: Theme.cardRadius)
    }
}

/// Dosya tablosu sütun başlıkları: Ad · Boyut · Değiştirilme.
struct FileTableHeader: View {
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Text("Ad").frame(maxWidth: .infinity, alignment: .leading)
                Text("Boyut").frame(width: 90, alignment: .leading)
                Text("Değiştirilme").frame(width: 140, alignment: .leading)
                Color.clear.frame(width: 52, height: 1)
            }
            .font(.callout)
            .foregroundStyle(Theme.secondaryText)
            .padding(.vertical, 6)
            .padding(.horizontal, 6)
            Rectangle().fill(Theme.divider).frame(height: 1)
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
            HStack(spacing: 10) {
                PDFBadge()
                Text(entry.name)
                    .font(.body.weight(.medium))
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if !entry.exists {
                    Text("Bulunamadı").font(.callout).foregroundStyle(Theme.secondaryText)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text(Fmt.fileSize(entry.size))
                .font(.body)
                .monospacedDigit()
                .foregroundStyle(Theme.secondaryText)
                .frame(width: 90, alignment: .leading)
            Text(Fmt.relativeDate(entry.date))
                .font(.body)
                .monospacedDigit()
                .foregroundStyle(Theme.secondaryText)
                .lineLimit(1)
                .frame(width: 140, alignment: .leading)
            HStack(spacing: 2) {
                if library.isStarred(entry.url) {
                    Image(systemName: "star.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.orange)
                        .accessibilityLabel("Yıldızlı")
                } else {
                    Color.clear.frame(width: 12, height: 12)
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
                        .foregroundStyle(Theme.secondaryText)
                        .frame(width: 24, height: 24)
                }
                .menuStyle(.button)
                .buttonStyle(.borderless)
                .menuIndicator(.hidden)
                .frame(width: 30)
                .accessibilityLabel("Dosya seçenekleri")
            }
            .frame(width: 52, alignment: .trailing)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 6)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(hover ? Theme.card2.opacity(0.7) : Color.clear))
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
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(kind == .recent ? "Son Dosyalar" : "Yıldızlı")
                    .font(Theme.titleFont)
                    .foregroundStyle(Theme.text)
                Spacer()
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").foregroundStyle(Theme.secondaryText).accessibilityHidden(true)
                    TextField("Dosya adında ara", text: $query)
                        .textFieldStyle(.plain)
                }
                .padding(.horizontal, 14)
                .frame(width: 280, height: 34)
                .background(Capsule().fill(Theme.card))
            }
            .padding(.horizontal, 6)
            .padding(.top, 8)
            if entries.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: kind == .recent ? "clock" : "star")
                        .font(.system(size: 30))
                        .foregroundStyle(Theme.secondaryText)
                    Text(kind == .recent ? "Son açılan dosya yok." : "Yıldızlı dosya yok. Bir dosyayı yıldızlamak için görüntüleyicideki yıldız düğmesini veya listedeki ⋮ menüsünü kullanın.")
                        .foregroundStyle(Theme.secondaryText)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 380)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 50)
                .qCard(radius: Theme.cardRadius)
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        FileTableHeader()
                        ForEach(Array(entries.enumerated()), id: \.element.id) { i, e in
                            FileRow(entry: e)
                            if i < entries.count - 1 {
                                Rectangle().fill(Theme.divider).frame(height: 1)
                            }
                        }
                    }
                    .padding(.horizontal, 18)
                    .padding(.vertical, 12)
                    .qCard(radius: Theme.cardRadius)
                }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: 1240, alignment: .leading)
    }
}
