import SwiftUI
import AppKit

@main
struct QeniroPDFApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var appState = AppState()

    var body: some Scene {
        Window("Qeniro PDF", id: "main") {
            ContentView()
                .environmentObject(appState)
                .environmentObject(appState.library)
                .environmentObject(SignatureStore.shared)
                .frame(minWidth: 980, minHeight: 640)
                .onAppear { appDelegate.attach(appState) }
        }
        .defaultSize(width: 1280, height: 820)
        .commands { AppCommands(appState: appState) }

        Settings {
            SettingsView()
                .environmentObject(appState)
                .environmentObject(SignatureStore.shared)
        }
    }
}

/// Finder'dan açılan dosyaları ve çıkış onayını yönetir.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private weak var appState: AppState?
    private var pending: [URL] = []

    func attach(_ state: AppState) {
        appState = state
        let urls = pending
        pending = []
        for u in urls { state.open(u) }
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        if let s = appState {
            for u in urls { s.open(u) }
            NSApp.activate(ignoringOtherApps: true)
        } else {
            pending.append(contentsOf: urls)
        }
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        appState?.confirmQuit() ?? .terminateNow
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

struct AppCommands: Commands {
    @ObservedObject var appState: AppState

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("PDF Aç…") { appState.openPanel() }
                .keyboardShortcut("o")
            Button("PDF Oluştur…") { appState.perform(.create) }
                .keyboardShortcut("n")
            Divider()
            Button("Sekmeyi Kapat") {
                if let s = appState.activeSession { appState.close(s) }
            }
            .keyboardShortcut("w", modifiers: [.command, .option])
            .disabled(appState.activeSession == nil)
        }
        CommandGroup(replacing: .saveItem) {
            Button("Kaydet") { _ = appState.activeSession?.save() }
                .keyboardShortcut("s")
                .disabled(appState.activeSession == nil)
            Button("Farklı Kaydet…") { _ = appState.activeSession?.saveAs() }
                .keyboardShortcut("s", modifiers: [.command, .shift])
                .disabled(appState.activeSession == nil)
        }
        CommandGroup(replacing: .printItem) {
            Button("Yazdır…") { appState.activeSession?.printDocument() }
                .keyboardShortcut("p")
                .disabled(appState.activeSession == nil)
        }
        CommandGroup(replacing: .undoRedo) {
            Button("Geri Al") { appState.undo() }
                .keyboardShortcut("z")
            Button("Yinele") { appState.redo() }
                .keyboardShortcut("z", modifiers: [.command, .shift])
        }
        CommandMenu("Belge") {
            Button("Bul…") {
                appState.activeSession?.isSearching = true
            }
            .keyboardShortcut("f")
            .disabled(appState.activeSession == nil)
            Divider()
            Button("Yakınlaştır") { appState.activeSession?.zoomIn() }
                .keyboardShortcut("+")
            Button("Uzaklaştır") { appState.activeSession?.zoomOut() }
                .keyboardShortcut("-")
            Button("Gerçek Boyut") { appState.activeSession?.setZoom(1) }
                .keyboardShortcut("0")
            Button("Sayfaya Sığdır") { appState.activeSession?.fitPage() }
                .keyboardShortcut("9")
            Divider()
            Button("Önceki Sayfa") { appState.activeSession?.previousPage() }
                .keyboardShortcut(.upArrow, modifiers: [.command, .option])
            Button("Sonraki Sayfa") { appState.activeSession?.nextPage() }
                .keyboardShortcut(.downArrow, modifiers: [.command, .option])
            Button("Sola Döndür") { appState.activeSession?.rotateCurrent(by: -90) }
                .keyboardShortcut("l")
            Button("Sağa Döndür") { appState.activeSession?.rotateCurrent(by: 90) }
                .keyboardShortcut("r")
            Divider()
            Button("PDF Düzenle") { appState.perform(.edit) }
                .keyboardShortcut("e")
            Button("İmzala ve Doldur") { appState.perform(.signFill) }
                .keyboardShortcut("e", modifiers: [.command, .shift])
            Button("PDF Sayfaları Düzenle") { appState.perform(.organize) }
            Button("PDF'de Sansürle") { appState.perform(.redact) }
            Button("Metin Tanıma (OCR)") { appState.activeSession?.runOCR(force: false) }
                .disabled(appState.activeSession == nil)
            Divider()
            Button("Seçili Öğeyi Sil") { appState.activeSession?.deleteSelected() }
                .disabled(appState.activeSession?.selectedAnnotation == nil)
        }
    }
}
