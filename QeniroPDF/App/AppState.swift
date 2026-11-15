import SwiftUI
import AppKit
import PDFKit
import UniformTypeIdentifiers

enum MainTab: Equatable {
    case shell
    case document(UUID)
}

/// Araç penceresi (sheet) isteği.
struct ToolSheetRequest: Identifiable {
    let id = UUID()
    let kind: ToolKind
    let files: [URL]
    let sessionID: UUID?
}

/// Uygulamanın genel durumu: açık sekmeler, kenar çubuğu seçimi, araç pencereleri.
@MainActor
final class AppState: ObservableObject {
    @Published var sessions: [DocumentSession] = []
    @Published var tab: MainTab = .shell
    @Published var sidebar: SidebarItem = .home
    @Published var sheet: ToolSheetRequest?
    @Published private(set) var notices: [AppNotice] = []
    @Published var unreadNotices = 0

    let library = FileLibrary()

    var activeSession: DocumentSession? {
        if case .document(let id) = tab { return sessions.first { $0.id == id } }
        return nil
    }

    func session(id: UUID?) -> DocumentSession? {
        guard let id else { return nil }
        return sessions.first { $0.id == id }
    }

    // MARK: - Açma / kapama

    func openPanel() {
        for url in Dialogs.openPDFs(multiple: true, title: "PDF Aç") { open(url) }
    }

    @discardableResult
    func open(_ url: URL, panel: SidePanel? = nil) -> DocumentSession? {
        if let existing = sessions.first(where: { $0.url?.standardizedFileURL == url.standardizedFileURL }) {
            tab = .document(existing.id)
            if let panel { existing.panel = panel }
            return existing
        }
        guard url.pathExtension.lowercased() == "pdf" || (try? url.resourceValues(forKeys: [.contentTypeKey]).contentType?.conforms(to: .pdf)) == true else {
            Dialogs.info("PDF değil", "\"\(url.lastPathComponent)\" bir PDF dosyası değil. Başka türdeki dosyaları PDF Oluştur aracıyla dönüştürebilirsiniz.")
            return nil
        }
        guard let doc = PDFDocument(url: url) else {
            Dialogs.error("Açılamadı", QPDFError.cannotOpen(url.lastPathComponent))
            return nil
        }
        var password: String?
        if doc.isLocked {
            var unlocked = false
            for attempt in 0..<3 {
                guard let pw = Dialogs.askText("\"\(url.lastPathComponent)\" şifre korumalı",
                                               message: attempt == 0 ? "Belgeyi açmak için şifreyi girin." : "Şifre yanlış. Lütfen tekrar deneyin.",
                                               placeholder: "Şifre", secure: true) else { return nil }
                if doc.unlock(withPassword: pw) { password = pw; unlocked = true; break }
            }
            guard unlocked else { return nil }
        }
        let s = DocumentSession(document: doc, url: url, password: password)
        attach(s)
        library.noteOpened(url)
        if let panel { s.panel = panel }
        return s
    }

    /// Kaydedilmemiş yeni bir belgeyi sekmede açar.
    @discardableResult
    func openUnsaved(_ doc: PDFDocument, name: String) -> DocumentSession {
        let s = DocumentSession(document: doc, url: nil)
        s.untitledName = name.hasSuffix(".pdf") ? name : name + ".pdf"
        s.isDirty = true
        attach(s)
        return s
    }

    private func attach(_ s: DocumentSession) {
        s.onSaved = { [weak self] url in
            MainActor.assumeIsolated { self?.library.noteOpened(url) }
        }
        sessions.append(s)
        tab = .document(s.id)
    }

    /// Sekmeyi kapatır; kaydedilmemiş değişiklik varsa sorar.
    @discardableResult
    func close(_ s: DocumentSession) -> Bool {
        if s.isDirty {
            switch Dialogs.askSaveChanges(name: s.displayName) {
            case .save: if !s.save() { return false }
            case .discard: break
            case .cancel: return false
            }
        }
        guard let i = sessions.firstIndex(where: { $0.id == s.id }) else { return true }
        sessions.remove(at: i)
        if case .document(let id) = tab, id == s.id {
            if sessions.isEmpty {
                tab = .shell
            } else {
                tab = .document(sessions[max(0, i - 1)].id)
            }
        }
        return true
    }

    func confirmQuit() -> NSApplication.TerminateReply {
        for s in sessions where s.isDirty {
            tab = .document(s.id)
            switch Dialogs.askSaveChanges(name: s.displayName) {
            case .save: if !s.save() { return .terminateCancel }
            case .discard: continue
            case .cancel: return .terminateCancel
            }
        }
        return .terminateNow
    }

    func showShell(_ item: SidebarItem) {
        sidebar = item
        tab = .shell
    }

    // MARK: - Araçlar

    func perform(_ tool: ToolKind) {
        switch tool {
        case .edit:
            withDocument { s in
                s.showOrganizer = false
                s.viewerTab = .edit
                s.panel = .tab
                s.tool = .editText
            }
        case .signFill:
            withDocument { s in
                s.showOrganizer = false
                s.viewerTab = .sign
                s.panel = .tab
                s.tool = .select
            }
        case .redact:
            withDocument { s in s.showOrganizer = false; s.panel = .redact; s.tool = .redact }
        case .organize:
            withDocument { s in s.showOrganizer = true }
        case .certificateSign:
            withDocument { [weak self] s in
                self?.sheet = ToolSheetRequest(kind: .certificateSign, files: s.url.map { [$0] } ?? [], sessionID: s.id)
            }
        default:
            let s = activeSession
            sheet = ToolSheetRequest(kind: tool, files: s?.url.map { [$0] } ?? [], sessionID: s?.id)
        }
    }

    private func withDocument(_ configure: (DocumentSession) -> Void) {
        if let s = activeSession { configure(s); return }
        guard let url = Dialogs.openPDFs(title: "Bir PDF seçin").first, let s = open(url) else { return }
        configure(s)
    }

    // MARK: - Geri al / yinele

    func undo() {
        if let r = NSApp.keyWindow?.firstResponder, r is NSText {
            NSApp.sendAction(Selector(("undo:")), to: nil, from: nil)
            return
        }
        guard let s = activeSession, s.undoManager.canUndo else { return }
        s.undoManager.undo()
        s.pdfView.refreshOverlay()
    }

    func redo() {
        if let r = NSApp.keyWindow?.firstResponder, r is NSText {
            NSApp.sendAction(Selector(("redo:")), to: nil, from: nil)
            return
        }
        guard let s = activeSession, s.undoManager.canRedo else { return }
        s.undoManager.redo()
        s.pdfView.refreshOverlay()
    }

    // MARK: - Bildirimler

    func notice(_ message: String, urls: [URL] = []) {
        notices.insert(AppNotice(message: message, urls: urls), at: 0)
        if notices.count > 50 { notices.removeLast() }
        unreadNotices += 1
        for u in urls where u.pathExtension.lowercased() == "pdf" { library.noteOpened(u) }
    }

    func markNoticesRead() { unreadNotices = 0 }
}
