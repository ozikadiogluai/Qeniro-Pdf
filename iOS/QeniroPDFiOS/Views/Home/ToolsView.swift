import SwiftUI

/// Tüm Araçlar sekmesi: üç bölüm halinde araç listesi.
struct ToolsView: View {
    var startTool: (ToolKind) -> Void

    let sections: [(String, [ToolKind])] = [
        (String(localized: "Oluştur ve Dönüştür"), [.createPDF, .toWord, .toExcel, .toPowerPoint]),
        (String(localized: "Düzenle ve Organize Et"), [.editPDF, .merge, .split, .organize, .compress]),
        (String(localized: "İmzala ve Koruyun"), [.sign, .protect, .redact]),
        (String(localized: "Diğer"), [.ocr, .convert])
    ]

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Tüm Araçlar")
                        .font(.largeTitle.weight(.bold))
                        .foregroundStyle(Theme.text)
                        .padding(.top, 14)
                        .padding(.bottom, 10)
                    ForEach(Array(sections.enumerated()), id: \.offset) { si, section in
                        SectionLabel(text: section.0)
                            .padding(.horizontal, 4)
                            .padding(.top, si == 0 ? 6 : 10)
                        VStack(spacing: 0) {
                            ForEach(Array(section.1.enumerated()), id: \.element.id) { i, t in
                                ToolListRow(tool: t, showDivider: i < section.1.count - 1) { startTool(t) }
                            }
                        }
                        .card()
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 24)
            }
        }
    }
}

/// Dosyalar sekmesi: Dosyalar uygulamasından PDF seçme ve son açılanların tam listesi.
struct FilesView: View {
    @EnvironmentObject private var library: FileLibrary
    @EnvironmentObject private var app: AppModel
    var openFile: () -> Void

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        Button(action: openFile) {
                            HStack(spacing: 12) {
                                Image(systemName: "folder")
                                    .font(.system(size: 18))
                                    .foregroundStyle(Theme.ink)
                                    .frame(width: 44, height: 44)
                                    .background(Theme.card2, in: Circle())
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Dosyalar'da gözat").font(.subheadline.weight(.semibold)).foregroundStyle(Theme.text)
                                    Text("iCloud Drive, iPhone'umda, Google Drive…").font(.caption).foregroundStyle(Theme.secondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right").flipsForRightToLeftLayoutDirection(true).font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.chevron)
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .card()
                        }
                        .buttonStyle(.plain)

                        Button {
                            if DocumentScannerView.isSupported { app.showScanner = true }
                            else { app.errorMessage = String(localized: "Bu cihazda belge tarayıcı kullanılamıyor.") }
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "doc.viewfinder")
                                    .font(.system(size: 18))
                                    .foregroundStyle(Theme.ink)
                                    .frame(width: 44, height: 44)
                                    .background(Theme.card2, in: Circle())
                                Text("Belge Tara").font(.subheadline.weight(.semibold)).foregroundStyle(Theme.text)
                                Spacer()
                                Image(systemName: "chevron.right").flipsForRightToLeftLayoutDirection(true).font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.chevron)
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .card()
                        }
                        .buttonStyle(.plain)

                        SectionLabel(text: String(localized: "Son açılanlar")).padding(.horizontal, 4).padding(.top, 8)
                        if library.recents.isEmpty {
                            Text("Henüz dosya yok.")
                                .font(.subheadline)
                                .foregroundStyle(Theme.secondary)
                                .frame(maxWidth: .infinity)
                                .padding(24)
                                .card()
                        } else {
                            VStack(spacing: 0) {
                                ForEach(Array(library.recents.enumerated()), id: \.element.id) { i, e in
                                    RecentRow(entry: e, showDivider: i < library.recents.count - 1)
                                }
                            }
                            .card()
                        }
                        Text("Taranan ve oluşturulan PDF'ler Dosyalar uygulamasında \"iPhone'umda > Qeniro PDF\" klasörüne kaydedilir.")
                            .font(.caption)
                            .foregroundStyle(Theme.secondary)
                            .padding(.horizontal, 4)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 12)
                }
            }
            .navigationTitle("Dosyalar")
            .toolbar {
                if !library.recents.isEmpty {
                    ToolbarItem(placement: .topBarTrailing) {
                        Menu {
                            Button(role: .destructive) { library.clearRecents() } label: { Label("Listeyi temizle", systemImage: "trash") }
                        } label: { Image(systemName: "ellipsis.circle") }
                    }
                }
            }
        }
    }
}

/// Yıldızlı dosyalar sekmesi.
struct StarredView: View {
    @EnvironmentObject private var library: FileLibrary

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background.ignoresSafeArea()
                if library.starred.isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: "star")
                            .font(.system(size: 34))
                            .foregroundStyle(Theme.chevron)
                        Text("Yıldızlı dosya yok")
                            .font(.headline)
                            .foregroundStyle(Theme.text)
                        Text("Bir dosyaya basılı tutup Yıldızla'yı seçin veya görüntüleyicide ••• menüsünü kullanın.")
                            .font(.subheadline)
                            .foregroundStyle(Theme.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 40)
                    }
                } else {
                    ScrollView {
                        VStack(spacing: 0) {
                            ForEach(Array(library.starred.enumerated()), id: \.element.id) { i, e in
                                RecentRow(entry: e, showDivider: i < library.starred.count - 1)
                            }
                        }
                        .card()
                        .padding(.horizontal, 12)
                        .padding(.vertical, 12)
                    }
                }
            }
            .navigationTitle("Yıldızlı")
        }
    }
}
