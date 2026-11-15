import SwiftUI

/// Ana Sayfa: logo, Hoş Geldiniz, arama, 8 hızlı araç, Belge Tara, Son Dosyalar, + düğmesi.
struct HomeView: View {
    @EnvironmentObject private var app: AppModel
    @EnvironmentObject private var library: FileLibrary
    var openFile: () -> Void
    var startTool: (ToolKind) -> Void
    @State private var query = ""

    let quickTools: [ToolKind] = [.editPDF, .createPDF, .merge, .split, .compress, .convert, .sign, .protect]
    let columns = Array(repeating: GridItem(.flexible(minimum: 0), spacing: 10), count: 4)

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Theme.background.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    header
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Hoş Geldiniz")
                            .font(.system(size: 28, weight: .bold))
                            .tracking(-0.56)
                            .foregroundStyle(Theme.text)
                        Text("Qeniro PDF'lerinizle daha fazlasını yapın.")
                            .font(.system(size: 15))
                            .foregroundStyle(Theme.secondary)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 4)

                    searchField
                        .padding(.horizontal, 20)
                        .padding(.top, 16)

                    if query.isEmpty {
                        LazyVGrid(columns: columns, spacing: 10) {
                            ForEach(quickTools) { t in
                                QuickToolCard(tool: t) { startTool(t) }
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 18)

                        scanBanner
                            .padding(.horizontal, 20)
                            .padding(.top, 14)
                    } else {
                        searchResults
                    }

                    recentsSection
                        .padding(.bottom, 110)
                }
            }
            .scrollDismissesKeyboard(.interactively)

            Button(action: openFile) {
                Image(systemName: "plus")
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 58, height: 58)
                    .background(Theme.accent, in: Circle())
                    .shadow(color: Theme.accent.opacity(0.35), radius: 10, x: 0, y: 8)
            }
            .accessibilityLabel("PDF aç")
            .padding(.trailing, 20)
            .padding(.bottom, 20)
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Text("Q")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 34, height: 34)
                .background(Theme.accent, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            Text("Qeniro PDF")
                .font(.system(size: 19, weight: .bold))
                .foregroundStyle(Theme.text)
            Spacer()
            Menu {
                Text("Yeni bildirim yok")
            } label: {
                Image(systemName: "bell")
                    .font(.system(size: 20))
                    .foregroundStyle(Theme.text)
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel("Bildirimler")
            Menu {
                Text("Qeniro PDF 1.0 (iPhone)")
                Text("Dosyalar uygulamasında: Qeniro PDF klasörü")
            } label: {
                Image(systemName: "person.circle")
                    .font(.system(size: 21))
                    .foregroundStyle(Theme.text)
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel("Hesap")
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 12)
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 16))
                .foregroundStyle(Theme.secondary)
            TextField("Dosya veya araç ara", text: $query)
                .font(.system(size: 15))
                .foregroundStyle(Theme.text)
                .submitLabel(.search)
            if !query.isEmpty {
                Button { query = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.chevron)
                }
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 44)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.border, lineWidth: 1))
    }

    private var scanBanner: some View {
        Button {
            if DocumentScannerView.isSupported {
                app.showScanner = true
            } else {
                app.errorMessage = "Bu cihazda belge tarayıcı kullanılamıyor (simülatörde kamera yoktur)."
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "camera")
                    .font(.system(size: 22))
                VStack(alignment: .leading, spacing: 1) {
                    Text("Belge Tara").font(.system(size: 15, weight: .semibold))
                    Text("Kamerayla çek, metni otomatik tanı (OCR)").font(.system(size: 12.5)).opacity(0.9)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.system(size: 15, weight: .semibold))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(Theme.accent, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var matchingTools: [ToolKind] {
        let q = query.lowercased(with: Fmt.trLocale)
        return ToolKind.allCases.filter { $0.title.lowercased(with: Fmt.trLocale).contains(q) }
    }

    private var searchResults: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !matchingTools.isEmpty {
                SectionLabel(text: "Araçlar").padding(.top, 18)
                VStack(spacing: 0) {
                    ForEach(Array(matchingTools.enumerated()), id: \.element.id) { i, t in
                        ToolListRow(tool: t, showDivider: i < matchingTools.count - 1) { startTool(t) }
                    }
                }
                .card()
            }
        }
        .padding(.horizontal, 20)
    }

    private var filteredRecents: [FileEntry] {
        guard !query.isEmpty else { return Array(library.recents.prefix(5)) }
        let q = query.lowercased(with: Fmt.trLocale)
        return library.recents.filter { $0.name.lowercased(with: Fmt.trLocale).contains(q) }
    }

    private var recentsSection: some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text(query.isEmpty ? "Son Dosyalar" : "Dosyalar")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(Theme.text)
                Spacer()
                if query.isEmpty && !library.recents.isEmpty {
                    Button("Tümü") { app.tab = .files }
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.blue)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 8)

            if filteredRecents.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.system(size: 28))
                        .foregroundStyle(Theme.chevron)
                    Text(query.isEmpty ? "Henüz dosya açmadınız. Sağ alttaki + ile bir PDF açın." : "Eşleşen dosya yok.")
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(24)
                .card()
                .padding(.horizontal, 20)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(filteredRecents.enumerated()), id: \.element.id) { i, e in
                        RecentRow(entry: e, showDivider: i < filteredRecents.count - 1)
                    }
                }
                .card()
                .padding(.horizontal, 20)
            }
        }
    }
}

/// Ana sayfadaki 4x2 hızlı araç kartı.
struct QuickToolCard: View {
    let tool: ToolKind
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: tool.icon)
                    .font(.system(size: 22, weight: .regular))
                    .foregroundStyle(tool.tint)
                    .frame(height: 26)
                Text(tool.shortTitle)
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(Theme.text)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
            }
            .frame(maxWidth: .infinity, minHeight: 72)
            .padding(.vertical, 12)
            .padding(.horizontal, 4)
            .card()
        }
        .buttonStyle(.plain)
    }
}

/// Son dosyalar satırı (dokun: aç; basılı tut: menü).
struct RecentRow: View {
    @EnvironmentObject private var app: AppModel
    @EnvironmentObject private var library: FileLibrary
    let entry: FileEntry
    let showDivider: Bool

    var body: some View {
        VStack(spacing: 0) {
            Button { app.open(entry) } label: {
                FileRow(entry: entry, starred: library.isStarred(entry))
            }
            .buttonStyle(.plain)
            .contextMenu {
                Button { app.open(entry) } label: { Label("Aç", systemImage: "doc") }
                Button { library.toggleStar(entry) } label: {
                    Label(library.isStarred(entry) ? "Yıldızı kaldır" : "Yıldızla", systemImage: library.isStarred(entry) ? "star.slash" : "star")
                }
                Button {
                    app.shareItem = ShareItem(urls: [entry.resolvedURL()])
                } label: { Label("Paylaş", systemImage: "square.and.arrow.up") }
                Button(role: .destructive) { library.removeRecent(entry) } label: {
                    Label("Listeden kaldır", systemImage: "trash")
                }
            }
            if showDivider {
                Rectangle().fill(Theme.divider).frame(height: 1)
            }
        }
    }
}

/// Bölüm listelerindeki araç satırı (Tüm Araçlar sekmesindeki görünüm).
struct ToolListRow: View {
    let tool: ToolKind
    let showDivider: Bool
    let action: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Button(action: action) {
                HStack(spacing: 12) {
                    Image(systemName: tool.icon)
                        .font(.system(size: 18))
                        .foregroundStyle(tool.tint)
                        .frame(width: 24)
                    Text(tool.title)
                        .font(.system(size: 15.5))
                        .foregroundStyle(Theme.text)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.chevron)
                }
                .padding(.horizontal, 14)
                .frame(minHeight: 48)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if showDivider {
                Rectangle().fill(Theme.divider).frame(height: 1)
            }
        }
    }
}
