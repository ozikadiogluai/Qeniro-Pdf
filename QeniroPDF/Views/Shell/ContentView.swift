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
                Divider()
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
        .background(Theme.window)
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
        HStack(spacing: 0) {
            SidebarView()
                .frame(width: Theme.sidebarWidth)
            Divider()
            ZStack(alignment: .topTrailing) {
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
                TopIconsView()
                    .padding(.top, 20)
                    .padding(.trailing, 24)
            }
            .background(Theme.background)
        }
        .navigationTitle("Qeniro PDF")
    }
}

struct SidebarView: View {
    @EnvironmentObject var app: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 8) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 30, height: 30)
                Text("Qeniro PDF")
                    .font(.system(size: 17, weight: .bold))
            }
            .padding(.horizontal, 6)
            .padding(.bottom, 18)
            .padding(.top, 6)

            ForEach(SidebarItem.allCases) { item in
                let active = app.sidebar == item
                Button {
                    app.showShell(item)
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: item.symbol)
                            .frame(width: 18)
                        Text(item.title)
                        Spacer()
                    }
                    .font(.system(size: 13, weight: active ? .semibold : .regular))
                    .foregroundStyle(active ? Theme.selection : Color.primary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(RoundedRectangle(cornerRadius: 7).fill(active ? Theme.activeNav : Color.clear))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            Spacer()
            Button {
                app.openPanel()
            } label: {
                Label("PDF Aç", systemImage: "folder")
                    .frame(maxWidth: .infinity)
            }
            .controlSize(.large)
            .buttonStyle(.borderedProminent)
            .tint(Theme.accent)
        }
        .padding(12)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Theme.sidebar)
    }
}

struct TabBarView: View {
    @EnvironmentObject var app: AppState

    var body: some View {
        HStack(spacing: 2) {
            tabButton("Ana Sayfa", active: app.tab == .shell && app.sidebar != .tools) { app.showShell(.home) }
            tabButton("Araçlar", active: app.tab == .shell && app.sidebar == .tools) { app.showShell(.tools) }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 2) {
                    ForEach(app.sessions) { s in
                        DocumentTab(session: s, active: app.tab == .document(s.id))
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Theme.sidebar)
    }

    private func tabButton(_ title: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: active ? .semibold : .regular))
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background(RoundedRectangle(cornerRadius: 7).fill(active ? Theme.window : Color.clear))
                .contentShape(Rectangle())
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
                .foregroundStyle(Theme.accent)
                .font(.system(size: 11))
            Text(session.displayName)
                .lineLimit(1)
                .font(.system(size: 13, weight: active ? .semibold : .regular))
                .frame(maxWidth: 200)
            Button {
                app.close(session)
            } label: {
                Image(systemName: session.isDirty && !hover ? "circle.fill" : "xmark")
                    .font(.system(size: session.isDirty && !hover ? 7 : 9, weight: .bold))
                    .frame(width: 14, height: 14)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Sekmeyi kapat")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 7).fill(active ? Theme.window : (hover ? Theme.window.opacity(0.5) : Color.clear)))
        .contentShape(Rectangle())
        .onHover { hover = $0 }
        .onTapGesture { app.tab = .document(session.id) }
    }
}

struct TopIconsView: View {
    @EnvironmentObject var app: AppState
    @State private var showHelp = false
    @State private var showNotices = false
    @State private var showAccount = false

    var body: some View {
        HStack(spacing: 16) {
            Button { showHelp.toggle() } label: { Image(systemName: "questionmark.circle") }
                .popover(isPresented: $showHelp, arrowEdge: .bottom) { HelpPopover() }
                .help("Yardım")
            Button {
                showNotices.toggle()
                app.markNoticesRead()
            } label: {
                Image(systemName: app.unreadNotices > 0 ? "bell.badge" : "bell")
            }
            .popover(isPresented: $showNotices, arrowEdge: .bottom) { NoticesPopover() }
            .help("Bildirimler")
            Button { showAccount.toggle() } label: { Image(systemName: "person.crop.circle") }
                .popover(isPresented: $showAccount, arrowEdge: .bottom) { AccountPopover() }
                .help("Hesap")
        }
        .buttonStyle(.plain)
        .font(.system(size: 17))
        .foregroundStyle(.secondary)
    }
}

struct HelpPopover: View {
    let shortcuts: [(String, String)] = [
        ("⌘O", "PDF aç"), ("⌘N", "PDF oluştur"), ("⌘S", "Kaydet"), ("⇧⌘S", "Farklı kaydet"),
        ("⌘P", "Yazdır"), ("⌘F", "Belgede ara"), ("⌘+ / ⌘−", "Yakınlaştır / uzaklaştır"),
        ("⌘0", "Gerçek boyut"), ("⌘L / ⌘R", "Sayfayı döndür"), ("⌘Z / ⇧⌘Z", "Geri al / yinele"),
        ("⌘E", "PDF Düzenle"), ("⇧⌘E", "İmzala ve Doldur"), ("⌫", "Seçili öğeyi sil"), ("Ok tuşları", "Seçili öğeyi kaydır (⇧ ile 10 pt)")
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
                Image(systemName: "person.crop.circle.fill").font(.system(size: 34)).foregroundStyle(Theme.accent)
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
