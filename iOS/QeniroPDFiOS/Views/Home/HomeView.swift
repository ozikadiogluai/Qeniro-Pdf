import SwiftUI
import UIKit

/// Ana Sayfa: lacivert kahraman alan (logo, karşılama, arama, 5 hızlı araç), Belge Tara kartı,
/// Son Dosyalar kartı ve diğer araçlar kartı. Alttaki hap menü RootView'dadır.
struct HomeView: View {
    @EnvironmentObject private var app: AppModel
    @EnvironmentObject private var library: FileLibrary
    var openFile: () -> Void
    var startTool: (ToolKind) -> Void
    @State private var query = ""
    @AppStorage(AppearanceChoice.storageKey) private var appearanceRaw = AppearanceChoice.system.rawValue

    let heroTools: [ToolKind] = [.editPDF, .sign, .convert, .merge, .compress]
    let moreTools: [ToolKind] = [.protect, .split, .redact, .ocr]
    let gridColumns = Array(repeating: GridItem(.flexible(minimum: 0), spacing: 10), count: 2)

    var body: some View {
        ZStack(alignment: .top) {
            Theme.background.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    hero
                    if query.isEmpty {
                        scanCard
                            .padding(.top, 4)
                        recentsSection
                        moreToolsCard
                    } else {
                        searchResults
                        recentsSection
                    }
                }
                .padding(.bottom, 24)
            }
            .scrollDismissesKeyboard(.interactively)
        }
    }

    // MARK: Kahraman

    private var hero: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 8) {
                Image("QeniroLogo")
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 40, height: 40)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 0) {
                    Text("Qeniro PDF")
                        .font(.footnote)
                        .foregroundStyle(Color.white.opacity(0.72))
                    Text("Hoş geldin")
                        .font(.headline)
                        .foregroundStyle(Color.white)
                }
                Spacer()
                Menu {
                    Section("Bildirimler") {
                        Text("Yeni bildirim yok")
                    }
                    Section("Ayarlar") {
                        Picker("Görünüm", selection: $appearanceRaw) {
                            ForEach(AppearanceChoice.allCases) { Text($0.title).tag($0.rawValue) }
                        }
                        .pickerStyle(.menu)
                        // Uygulama dili iOS Ayarlar > Qeniro PDF > Dil bölümünden seçilir.
                        Button {
                            if let u = URL(string: UIApplication.openSettingsURLString) {
                                UIApplication.shared.open(u)
                            }
                        } label: {
                            Label("Dil: \(Fmt.appLanguageName)", systemImage: "globe")
                        }
                    }
                    Section {
                        Text("Qeniro PDF 1.0 (iPhone)")
                        Text("Dosyalar uygulamasında: Qeniro PDF klasörü")
                    }
                } label: {
                    Image(systemName: "bell")
                        .font(.system(size: 18))
                        .foregroundStyle(Color.white)
                        .frame(width: 44, height: 44)
                        .background(Color.white.opacity(0.09), in: Circle())
                }
                .accessibilityLabel("Bildirimler ve ayarlar")
            }

            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 16))
                    .accessibilityHidden(true)
                TextField("", text: $query, prompt: Text("Dosya veya araç ara").foregroundStyle(Color.white.opacity(0.78)))
                    .font(.subheadline)
                    .foregroundStyle(Color.white)
                    .tint(Color.white)
                    .submitLabel(.search)
                    .accessibilityLabel("Dosya veya araç ara")
                if !query.isEmpty {
                    Button { query = "" } label: {
                        Image(systemName: "xmark.circle.fill").frame(width: 32, height: 44)
                    }
                    .accessibilityLabel("Aramayı temizle")
                }
            }
            .foregroundStyle(Color.white.opacity(0.78))
            .padding(.horizontal, 14)
            .frame(minHeight: 44)
            .background(Color.white.opacity(0.10), in: Capsule())

            HStack(alignment: .top, spacing: 0) {
                ForEach(heroTools) { t in
                    Button { startTool(t) } label: {
                        VStack(spacing: 6) {
                            Image(systemName: t.icon)
                                .font(.system(size: 20))
                                .foregroundStyle(Color.white)
                                .frame(width: 50, height: 50)
                                .background(Color.white.opacity(0.12), in: Circle())
                            Text(t.heroTitle)
                                .font(.caption)
                                .foregroundStyle(Color.white)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                        }
                        .frame(maxWidth: .infinity)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(t.title)
                }
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 14)
        .padding(.bottom, 20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            UnevenRoundedRectangle(bottomLeadingRadius: 34, bottomTrailingRadius: 34, style: .continuous)
                .fill(Theme.heroGradient())
                .ignoresSafeArea(edges: .top)
        )
    }

    // MARK: Belge Tara

    private var scanCard: some View {
        HStack(spacing: 12) {
            Image(systemName: "camera")
                .font(.system(size: 19))
                .foregroundStyle(Theme.ink)
                .frame(width: 44, height: 44)
                .background(Theme.card2, in: Circle())
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("Belge Tara").font(.subheadline.weight(.semibold)).foregroundStyle(Theme.text)
                Text("Kamerayla çek, metni otomatik tanı").font(.caption).foregroundStyle(Theme.secondary)
            }
            Spacer(minLength: 4)
            Button {
                if DocumentScannerView.isSupported {
                    app.showScanner = true
                } else {
                    app.errorMessage = String(localized: "Bu cihazda belge tarayıcı kullanılamıyor (simülatörde kamera yoktur).")
                }
            } label: {
                Text("Tara")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Theme.onInk)
                    .padding(.horizontal, 16)
                    .frame(height: 36)
                    .background(Theme.ink, in: Capsule())
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .card()
        .padding(.horizontal, 12)
    }

    // MARK: Diğer araçlar

    private var moreToolsCard: some View {
        LazyVGrid(columns: gridColumns, alignment: .leading, spacing: 10) {
            ForEach(moreTools) { t in
                Button { startTool(t) } label: {
                    HStack(spacing: 10) {
                        Image(systemName: t.icon)
                            .font(.system(size: 15))
                            .foregroundStyle(Theme.ink)
                            .frame(width: 34, height: 34)
                            .background(Theme.card2, in: Circle())
                        Text(t.gridTitle)
                            .font(.subheadline)
                            .foregroundStyle(Theme.text)
                            .lineLimit(2)
                            .minimumScaleFactor(0.85)
                        Spacer(minLength: 0)
                    }
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .card()
        .padding(.horizontal, 12)
    }

    // MARK: Arama

    private var matchingTools: [ToolKind] {
        let q = query.lowercased(with: Fmt.locale)
        return ToolKind.allCases.filter { $0.title.lowercased(with: Fmt.locale).contains(q) }
    }

    private var searchResults: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !matchingTools.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Araçlar")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.text)
                        .padding(.horizontal, 14)
                        .padding(.top, 12)
                        .padding(.bottom, 2)
                    ForEach(Array(matchingTools.enumerated()), id: \.element.id) { i, t in
                        ToolListRow(tool: t, showDivider: i < matchingTools.count - 1) { startTool(t) }
                    }
                }
                .card()
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 4)
    }

    private var filteredRecents: [FileEntry] {
        guard !query.isEmpty else { return Array(library.recents.prefix(5)) }
        let q = query.lowercased(with: Fmt.locale)
        return library.recents.filter { $0.name.lowercased(with: Fmt.locale).contains(q) }
    }

    // MARK: Son dosyalar

    private var recentsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text(query.isEmpty ? String(localized: "Son Dosyalar") : String(localized: "Dosyalar"))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.text)
                Spacer()
                if query.isEmpty && !library.recents.isEmpty {
                    Button("Tümü") { app.tab = .files }
                        .font(.footnote)
                        .foregroundStyle(Theme.secondary)
                        .frame(minHeight: 32)
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 10)

            if filteredRecents.isEmpty {
                VStack(spacing: 8) {
                    Text(query.isEmpty ? String(localized: "Henüz dosya açmadınız. Alttaki + ile bir PDF açın.") : String(localized: "Eşleşen dosya yok."))
                        .font(.subheadline)
                        .foregroundStyle(Theme.secondary)
                        .multilineTextAlignment(.center)
                    if query.isEmpty {
                        Button("PDF aç", action: openFile)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.onInk)
                            .padding(.horizontal, 18)
                            .frame(minHeight: 44)
                            .background(Theme.ink, in: Capsule())
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 18)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(filteredRecents.enumerated()), id: \.element.id) { i, e in
                        RecentRow(entry: e, showDivider: i < filteredRecents.count - 1)
                    }
                }
                .padding(.bottom, 4)
            }
        }
        .card()
        .padding(.horizontal, 12)
    }
}

extension ToolKind {
    /// Kahraman alandaki kısa ad.
    var heroTitle: String {
        switch self {
        case .editPDF: return String(localized: "Düzenle")
        case .sign: return String(localized: "İmzala")
        case .convert: return String(localized: "Dönüştür")
        case .merge: return String(localized: "Birleştir")
        case .compress: return String(localized: "Sıkıştır")
        default: return shortTitle
        }
    }

    /// Ana sayfa ızgara kartındaki ad.
    var gridTitle: String {
        switch self {
        case .protect: return String(localized: "Şifreyle koru")
        case .split: return String(localized: "Böl")
        case .redact: return String(localized: "Sansürle")
        case .ocr: return String(localized: "Metni tanı (OCR)")
        default: return title
        }
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
                    Label(library.isStarred(entry) ? String(localized: "Yıldızı kaldır") : String(localized: "Yıldızla"), systemImage: library.isStarred(entry) ? "star.slash" : "star")
                }
                Button {
                    app.shareItem = ShareItem(urls: [entry.resolvedURL()])
                } label: { Label("Paylaş", systemImage: "square.and.arrow.up") }
                Button(role: .destructive) { library.removeRecent(entry) } label: {
                    Label("Listeden kaldır", systemImage: "trash")
                }
            }
            if showDivider {
                Rectangle().fill(Theme.divider).frame(height: 1).padding(.leading, 14)
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
                        .font(.system(size: 15))
                        .foregroundStyle(Theme.ink)
                        .frame(width: 34, height: 34)
                        .background(Theme.card2, in: Circle())
                    Text(tool.title)
                        .font(.subheadline)
                        .foregroundStyle(Theme.text)
                    Spacer()
                    Image(systemName: "chevron.right").flipsForRightToLeftLayoutDirection(true)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.chevron)
                }
                .padding(.horizontal, 14)
                .frame(minHeight: 48)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if showDivider {
                Rectangle().fill(Theme.divider).frame(height: 1).padding(.leading, 60)
            }
        }
    }
}
