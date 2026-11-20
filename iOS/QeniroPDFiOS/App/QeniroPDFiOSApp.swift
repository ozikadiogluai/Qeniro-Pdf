import SwiftUI
import UniformTypeIdentifiers

@main
struct QeniroPDFiOSApp: App {
    @StateObject private var app = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(app)
                .environmentObject(app.library)
                .environmentObject(SignatureStore.shared)
                .tint(Theme.navy)
                // Dosyalar uygulaması, "Paylaş > Qeniro PDF ile aç" ve AirDrop ile gelen PDF'ler.
                .onOpenURL { url in
                    guard url.isFileURL else { return }
                    app.open(url)
                }
        }
    }
}

/// Dosya seçicinin hangi amaçla açıldığı.
enum ImportPurpose {
    case open
    case tool(ToolKind)
}

struct RootView: View {
    @EnvironmentObject private var app: AppModel
    @State private var showImporter = false
    @State private var importPurpose: ImportPurpose = .open
    @State private var password = ""
    @AppStorage(AppearanceChoice.storageKey) private var appearanceRaw = AppearanceChoice.system.rawValue

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            tabPage(.home) { HomeView(openFile: { requestImport(.open) }, startTool: startTool) }
            tabPage(.tools) { ToolsView(startTool: startTool) }
            tabPage(.files) { FilesView(openFile: { requestImport(.open) }) }
            tabPage(.starred) { StarredView() }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            HapTabBar(selection: $app.tab, onPlus: { requestImport(.open) })
        }
        .onAppear { (AppearanceChoice(rawValue: appearanceRaw) ?? .system).apply() }
        .onChange(of: appearanceRaw) { _, new in (AppearanceChoice(rawValue: new) ?? .system).apply() }
        .fileImporter(isPresented: $showImporter,
                      allowedContentTypes: [.pdf],
                      allowsMultipleSelection: isMultiple) { result in
            handleImport(result)
        }
        .sheet(item: $app.toolRun) { run in
            ToolRunnerView(run: run)
                .environmentObject(app)
        }
        .sheet(isPresented: $app.showCreate) {
            CreatePDFView()
                .environmentObject(app)
        }
        .sheet(item: $app.shareItem) { item in
            ActivityView(items: item.urls)
        }
        .background {
            // Ayrı bir görünüme bağlı tam ekran sunumlar (aynı görünümde birden çok sunum çakışmasın).
            Color.clear
                .fullScreenCover(isPresented: Binding(get: { app.showScanner && app.session == nil },
                                                      set: { app.showScanner = $0 })) {
                    DocumentScannerView(onFinish: { images in
                        app.showScanner = false
                        app.finishScan(images)
                    }, onCancel: {
                        app.showScanner = false
                    })
                    .ignoresSafeArea()
                }
        }
        .fullScreenCover(item: $app.session) { session in
            ViewerView(session: session)
                .environmentObject(app)
                .environmentObject(app.library)
                .environmentObject(SignatureStore.shared)
        }
        .alert("Şifreli PDF", isPresented: Binding(get: { app.passwordRequest != nil },
                                                   set: { if !$0 { app.passwordRequest = nil } }),
               presenting: app.passwordRequest) { req in
            SecureField("Şifre", text: $password)
            Button("Aç") {
                let pw = password
                password = ""
                app.unlock(req, password: pw)
            }
            Button("Vazgeç", role: .cancel) { password = "" }
        } message: { req in
            Text("\"\(req.url.lastPathComponent)\" şifreyle korunuyor. Açmak için şifreyi girin.")
        }
        .alert("Bir sorun oluştu", isPresented: Binding(get: { app.errorMessage != nil },
                                                       set: { if !$0 { app.errorMessage = nil } })) {
            Button("Tamam", role: .cancel) {}
        } message: {
            Text(app.errorMessage ?? "")
        }
        .overlay {
            if let msg = app.busyMessage { BusyOverlay(message: msg) }
        }
    }

    /// Sekme sayfaları bellekte kalır (kaydırma ve gezinme durumu korunur); yalnızca seçili olan görünür.
    @ViewBuilder
    private func tabPage<Content: View>(_ tab: MainTab, @ViewBuilder content: () -> Content) -> some View {
        let selected = app.tab == tab
        content()
            .opacity(selected ? 1 : 0)
            .allowsHitTesting(selected)
            .accessibilityHidden(!selected)
    }

    private var isMultiple: Bool {
        if case .tool(let t) = importPurpose { return t.multipleFiles }
        return false
    }

    private func requestImport(_ purpose: ImportPurpose) {
        importPurpose = purpose
        showImporter = true
    }

    private func startTool(_ tool: ToolKind) {
        switch tool {
        case .createPDF:
            app.showCreate = true
        default:
            requestImport(.tool(tool))
        }
    }

    private func handleImport(_ result: Result<[URL], Error>) {
        switch result {
        case .failure(let e):
            app.errorMessage = e.localizedDescription
        case .success(let urls):
            guard !urls.isEmpty else { return }
            switch importPurpose {
            case .open: app.open(urls[0])
            case .tool(let t): app.run(t, with: urls)
            }
        }
    }
}

/// iPhone ana sayfa hap menüsü: koyu kapsül, 44 pt daireler; sıra Ana Sayfa · Araçlar · [turuncu +] · Dosyalar · Yıldızlı.
struct HapTabBar: View {
    @Binding var selection: MainTab
    var onPlus: () -> Void
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 3) {
            item(.home, "house.fill", "Ana Sayfa")
            item(.tools, "square.grid.2x2.fill", "Araçlar")
            Button(action: onPlus) {
                Image(systemName: "plus")
                    .font(.system(size: 19, weight: .bold))
                    .foregroundStyle(Color.white)
                    .frame(width: 44, height: 44)
                    .background(Theme.plusGradient, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("PDF aç")
            item(.files, "folder.fill", "Dosyalar")
            item(.starred, "star.fill", "Yıldızlı")
        }
        .padding(4)
        .background(Theme.pill, in: Capsule())
        .overlay(Capsule().strokeBorder(Color.white.opacity(scheme == .dark ? 0.08 : 0), lineWidth: 0.5))
        .shadow(color: .black.opacity(scheme == .dark ? 0.4 : 0.22), radius: 10, x: 0, y: 6)
        .frame(maxWidth: .infinity)
        .padding(.top, 28)
        .padding(.bottom, 6)
        .background(
            LinearGradient(stops: [.init(color: Theme.background.opacity(0), location: 0),
                                   .init(color: Theme.background.opacity(0.92), location: 0.45),
                                   .init(color: Theme.background, location: 1)],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea(edges: .bottom)
                .allowsHitTesting(false)
        )
    }

    private func item(_ tab: MainTab, _ icon: String, _ label: String) -> some View {
        let selected = selection == tab
        return Button {
            if reduceMotion { selection = tab } else { withAnimation(.easeOut(duration: 0.15)) { selection = tab } }
        } label: {
            Image(systemName: icon)
                .font(.system(size: 17, weight: .regular))
                .foregroundStyle(selected ? Color(hex: 0x121A21) : Color.white)
                .frame(width: 44, height: 44)
                .background(selected ? Color.white : Color.white.opacity(0.07), in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
