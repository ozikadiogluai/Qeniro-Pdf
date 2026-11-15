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
                .tint(Theme.accent)
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

    var body: some View {
        TabView(selection: $app.tab) {
            HomeView(openFile: { requestImport(.open) }, startTool: startTool)
                .tabItem { Label("Ana Sayfa", systemImage: "house") }
                .tag(MainTab.home)
            ToolsView(startTool: startTool)
                .tabItem { Label("Araçlar", systemImage: "square.grid.2x2") }
                .tag(MainTab.tools)
            FilesView(openFile: { requestImport(.open) })
                .tabItem { Label("Dosyalar", systemImage: "folder") }
                .tag(MainTab.files)
            StarredView()
                .tabItem { Label("Yıldızlı", systemImage: "star") }
                .tag(MainTab.starred)
        }
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
