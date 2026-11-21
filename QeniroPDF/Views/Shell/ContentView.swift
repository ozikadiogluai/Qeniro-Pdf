import SwiftUI
import AppKit

struct ContentView: View {
    @EnvironmentObject var app: AppState
    @EnvironmentObject var library: FileLibrary
    @EnvironmentObject var signatures: SignatureStore

    var body: some View {
        VStack(spacing: 0) {
            if !app.sessions.isEmpty {
                TabBarView()
            }
            Group {
                switch app.tab {
                case .shell:
                    ShellView()
                case .document(let id):
                    if let s = app.session(id: id) {
                        ViewerView(session: s).id(s.id)
                    } else {
                        ShellView()
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Theme.background)
        .sheet(item: $app.sheet) { req in
            ToolSheetHost(request: req)
                .environmentObject(app)
                .environmentObject(library)
                .environmentObject(signatures)
        }
        .dropDestination(for: URL.self) { urls, _ in
            let pdfs = urls.filter { $0.pathExtension.lowercased() == "pdf" }
            let others = urls.filter { $0.pathExtension.lowercased() != "pdf" }
            for u in pdfs { app.open(u) }
            if !others.isEmpty {
                app.sheet = ToolSheetRequest(kind: .create, files: others, sessionID: nil)
            }
            return !urls.isEmpty
        }
    }
}

struct ShellView: View {
    @EnvironmentObject var app: AppState

    var body: some View {
        HStack(spacing: 10) {
            SidebarView()
                .frame(width: Theme.sidebarWidth)
            Group {
                switch app.sidebar {
                case .home: HomeView()
                case .tools: AllToolsView()
                case .recent: FileListPage(kind: .recent)
                case .starred: FileListPage(kind: .starred)
                case .cloud: CloudView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .padding(10)
        .background(Theme.background)
        .navigationTitle("Qeniro PDF")
    }
}

/// Sol kenar çubuğu: 220 pt, yarı saydam (cam), seçili öğe koyu kapsül-dikdörtgen.
struct SidebarView: View {
    @EnvironmentObject var app: AppState
    @AppStorage(AppearanceChoice.storageKey) private var appearanceRaw = AppearanceChoice.system.rawValue

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 10) {
                Text("Q")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Theme.onInk)
                    .frame(width: 30, height: 30)
                    .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Theme.ink))
                    .accessibilityHidden(true)
                Text("Qeniro PDF")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Theme.text)
            }
            .padding(.horizontal, 8)
            .padding(.top, 6)
            .padding(.bottom, 16)

            ForEach(SidebarItem.allCases) { item in
                let active = app.tab == .shell && app.sidebar == item
                Button {
                    app.showShell(item)
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: active ? item.symbol + ".fill" : item.symbol)
                            .frame(width: 18)
                        Text(item.title)
                        Spacer()
                    }
                    .font(.body.weight(active ? .medium : .regular))
                    .foregroundStyle(active ? Theme.onInk : Theme.text)
                    .padding(.horizontal, 10)
                    .frame(height: 34)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(active ? Theme.ink : Color.clear))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(active ? .isSelected : [])
            }
            Spacer()
            TopIconsView()
                .padding(.horizontal, 6)
                .padding(.bottom, 8)
            Menu {
                Picker("Görünüm", selection: $appearanceRaw) {
                    ForEach(AppearanceChoice.allCases) { Text($0.title).tag($0.rawValue) }
                }
                .pickerStyle(.inline)
                Divider()
                Section("Dil: \(Fmt.appLanguageName)") {
                    Text("Sistem Ayarları > Genel > Dil ve Bölge > Uygulamalar")
                    Button("Dil ve Bölge ayarlarını aç…") { LanguageSettings.open() }
                }
            } label: {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Tema").font(.callout.weight(.semibold)).foregroundStyle(Theme.text)
                    Text(String(localized: "Lacivert · ") + (AppearanceChoice(rawValue: appearanceRaw) ?? .system).title)
                        .font(.callout)
                        .foregroundStyle(Theme.secondaryText)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.card2))
                .contentShape(Rectangle())
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .help("Tema: açık, koyu veya sistemle aynı")
            .onChange(of: appearanceRaw) { _, new in
                (AppearanceChoice(rawValue: new) ?? .system).apply()
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 14)
        .frame(maxHeight: .infinity, alignment: .top)
        .qGlass(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

struct TabBarView: View {
    @EnvironmentObject var app: AppState

    var body: some View {
        HStack(spacing: 4) {
            tabButton(String(localized: "Ana Sayfa"), active: app.tab == .shell && app.sidebar != .tools) { app.showShell(.home) }
            tabButton(String(localized: "Araçlar"), active: app.tab == .shell && app.sidebar == .tools) { app.showShell(.tools) }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(app.sessions) { s in
                        DocumentTab(session: s, active: app.tab == .document(s.id))
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Theme.background)
    }

    private func tabButton(_ title: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.body.weight(active ? .semibold : .regular))
                .foregroundStyle(active ? Theme.onInk : Theme.text)
                .padding(.horizontal, 14)
                .frame(height: 28)
                .background(Capsule().fill(active ? Theme.ink : Color.clear))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

struct DocumentTab: View {
    @EnvironmentObject var app: AppState
    @ObservedObject var session: DocumentSession
    let active: Bool
    @State private var hover = false

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "doc.fill")
                .foregroundStyle(Theme.pdfBadgeText)
                .font(.system(size: 11))
                .accessibilityHidden(true)
            Text(session.displayName)
                .lineLimit(1)
                .font(.body.weight(active ? .semibold : .regular))
                .foregroundStyle(Theme.text)
                .frame(maxWidth: 200)
            Button {
                app.close(session)
            } label: {
                Image(systemName: session.isDirty && !hover ? "circle.fill" : "xmark")
                    .font(.system(size: session.isDirty && !hover ? 7 : 9, weight: .bold))
                    .foregroundStyle(Theme.secondaryText)
                    .frame(width: 16, height: 16)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Sekmeyi kapat")
            .accessibilityLabel("Sekmeyi kapat")
        }
        .padding(.horizontal, 12)
        .frame(height: 28)
        .background(Capsule().fill(active ? Theme.card : (hover ? Theme.card.opacity(0.6) : Color.clear)))
        .contentShape(Capsule())
        .onHover { hover = $0 }
        .onTapGesture { app.tab = .document(session.id) }
    }
}

/// Kenar çubuğunun altındaki küçük düğmeler: PDF aç, Yardım, Bildirimler, Hesap.
struct TopIconsView: View {
    @EnvironmentObject var app: AppState
    @State private var showHelp = false
    @State private var showNotices = false
    @State private var showAccount = false

    var body: some View {
        HStack(spacing: 6) {
            iconButton("plus", String(localized: "PDF aç (⌘O)")) { app.openPanel() }
            iconButton("questionmark", String(localized: "Yardım")) { showHelp.toggle() }
                .popover(isPresented: $showHelp, arrowEdge: .top) { HelpPopover() }
            iconButton(app.unreadNotices > 0 ? "bell.badge" : "bell", String(localized: "Bildirimler")) {
                showNotices.toggle()
                app.markNoticesRead()
            }
            .popover(isPresented: $showNotices, arrowEdge: .top) { NoticesPopover() }
            iconButton("person", String(localized: "Hesap")) { showAccount.toggle() }
                .popover(isPresented: $showAccount, arrowEdge: .top) { AccountPopover() }
            Spacer(minLength: 0)
        }
    }

    private func iconButton(_ symbol: String, _ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Theme.ink)
                .frame(width: 32, height: 32)
                .background(Circle().fill(Theme.card2))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(label)
        .accessibilityLabel(label)
    }
}

struct HelpPopover: View {
    let shortcuts: [(String, String)] = [
        ("⌘O", String(localized: "PDF aç")), ("⌘N", String(localized: "PDF oluştur")), ("⌘S", String(localized: "Kaydet")), ("⇧⌘S", String(localized: "Farklı kaydet")),
        ("⌘P", String(localized: "Yazdır")), ("⌘F", String(localized: "Belgede ara")), ("⌘+ / ⌘−", String(localized: "Yakınlaştır / uzaklaştır")),
        ("⌘0", String(localized: "Gerçek boyut")), ("⌘L / ⌘R", String(localized: "Sayfayı döndür")), ("⌘Z / ⇧⌘Z", String(localized: "Geri al / yinele")),
        ("⌘E", String(localized: "PDF Düzenle")), ("⇧⌘E", String(localized: "İmzala ve Doldur")), ("⌫", String(localized: "Seçili öğeyi sil")), (String(localized: "Ok tuşları"), String(localized: "Seçili öğeyi kaydır (⇧ ile 10 pt)"))
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Yardım").font(.headline)
            Text("PDF'leri pencereye sürükleyip bırakarak açabilirsiniz. Diğer dosya türleri (görsel, Word, metin) bırakıldığında PDF Oluştur aracı açılır.")
                .font(.callout).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Divider()
            Text("Klavye kısayolları").font(.subheadline.bold())
            Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 5) {
                ForEach(shortcuts.indices, id: \.self) { i in
                    let s = shortcuts[i]
                    GridRow {
                        Text(s.0).font(.system(.callout, design: .monospaced)).foregroundStyle(.secondary)
                        Text(s.1).font(.callout)
                    }
                }
            }
        }
        .padding(16)
        .frame(width: 340)
    }
}

struct NoticesPopover: View {
    @EnvironmentObject var app: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Bildirimler").font(.headline)
            if app.notices.isEmpty {
                Text("Henüz bildirim yok. Tamamlanan işlemler burada görünür.")
                    .font(.callout).foregroundStyle(.secondary)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(app.notices) { n in
                            VStack(alignment: .leading, spacing: 3) {
                                Text(n.message).font(.callout)
                                HStack {
                                    Text(Fmt.relativeDate(n.date)).font(.caption).foregroundStyle(.secondary)
                                    if !n.urls.isEmpty {
                                        Button("Finder'da göster") { Dialogs.revealInFinder(n.urls) }
                                            .buttonStyle(.link).font(.caption)
                                    }
                                }
                            }
                            Divider()
                        }
                    }
                }
                .frame(maxHeight: 320)
            }
        }
        .padding(16)
        .frame(width: 320)
    }
}

struct AccountPopover: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "person.crop.circle.fill").font(.system(size: 34)).foregroundStyle(Theme.ink)
                VStack(alignment: .leading) {
                    Text(NSFullUserName().isEmpty ? NSUserName() : NSFullUserName()).font(.headline)
                    Text("Yerel hesap · tüm işlemler bu Mac'te yapılır").font(.caption).foregroundStyle(.secondary)
                }
            }
            Divider()
            if #available(macOS 14.0, *) {
                SettingsLink { Text("Ayarlar…") }
            }
        }
        .padding(16)
        .frame(width: 300)
    }
}
