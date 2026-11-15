import AppKit
import UniformTypeIdentifiers

/// NSOpenPanel / NSSavePanel / NSAlert sarmalayıcıları (Türkçe).
@MainActor
enum Dialogs {
    static func openPDFs(multiple: Bool = false, title: String = "PDF Seçin") -> [URL] {
        openFiles(types: [.pdf], multiple: multiple, title: title)
    }

    static func openFiles(types: [UTType], multiple: Bool, title: String) -> [URL] {
        let panel = NSOpenPanel()
        panel.title = title
        panel.message = title
        panel.prompt = "Seç"
        panel.allowsMultipleSelection = multiple
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        if !types.isEmpty { panel.allowedContentTypes = types }
        return panel.runModal() == .OK ? panel.urls : []
    }

    static func chooseFolder(title: String = "Çıktı klasörünü seçin") -> URL? {
        let panel = NSOpenPanel()
        panel.title = title
        panel.message = title
        panel.prompt = "Seç"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        return panel.runModal() == .OK ? panel.url : nil
    }

    static func save(suggestedName: String, type: UTType?, title: String = "Kaydet", directory: URL? = nil) -> URL? {
        let panel = NSSavePanel()
        panel.title = title
        panel.prompt = "Kaydet"
        panel.nameFieldStringValue = suggestedName
        panel.canCreateDirectories = true
        if let type { panel.allowedContentTypes = [type] }
        if let directory { panel.directoryURL = directory }
        return panel.runModal() == .OK ? panel.url : nil
    }

    static func info(_ title: String, _ message: String = "") {
        let a = NSAlert()
        a.messageText = title
        a.informativeText = message
        a.alertStyle = .informational
        a.addButton(withTitle: "Tamam")
        a.runModal()
    }

    static func error(_ title: String, _ error: Error) {
        let a = NSAlert()
        a.messageText = title
        a.informativeText = error.localizedDescription
        a.alertStyle = .warning
        a.addButton(withTitle: "Tamam")
        a.runModal()
    }

    static func confirm(_ title: String, _ message: String, ok: String = "Devam", cancel: String = "Vazgeç") -> Bool {
        let a = NSAlert()
        a.messageText = title
        a.informativeText = message
        a.addButton(withTitle: ok)
        a.addButton(withTitle: cancel)
        return a.runModal() == .alertFirstButtonReturn
    }

    /// Tek satırlık metin girişi ister. Vazgeçilirse nil döner.
    static func askText(_ title: String, message: String = "", placeholder: String = "", initial: String = "", secure: Bool = false) -> String? {
        let a = NSAlert()
        a.messageText = title
        a.informativeText = message
        a.addButton(withTitle: "Tamam")
        a.addButton(withTitle: "Vazgeç")
        let field: NSTextField = secure ? NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 280, height: 24))
                                        : NSTextField(frame: NSRect(x: 0, y: 0, width: 280, height: 24))
        field.placeholderString = placeholder
        field.stringValue = initial
        a.accessoryView = field
        a.window.initialFirstResponder = field
        guard a.runModal() == .alertFirstButtonReturn else { return nil }
        return field.stringValue
    }

    enum SaveChoice { case save, discard, cancel }

    static func askSaveChanges(name: String) -> SaveChoice {
        let a = NSAlert()
        a.messageText = "\"\(name)\" belgesindeki değişiklikler kaydedilsin mi?"
        a.informativeText = "Kaydetmezseniz değişiklikleriniz kaybolur."
        a.addButton(withTitle: "Kaydet")
        a.addButton(withTitle: "Kaydetme")
        a.addButton(withTitle: "Vazgeç")
        switch a.runModal() {
        case .alertFirstButtonReturn: return .save
        case .alertSecondButtonReturn: return .discard
        default: return .cancel
        }
    }

    static func revealInFinder(_ urls: [URL]) {
        NSWorkspace.shared.activateFileViewerSelecting(urls)
    }
}

extension UTType {
    static let docx = UTType(filenameExtension: "docx") ?? .data
    static let xlsx = UTType(filenameExtension: "xlsx") ?? .data
    static let pptx = UTType(filenameExtension: "pptx") ?? .data
    static let officeInputs: [UTType] = ["docx", "doc", "rtf", "rtfd", "odt", "txt", "html", "htm", "xlsx", "xls", "pptx", "ppt", "odp", "ods", "pages", "numbers", "key"]
        .compactMap { UTType(filenameExtension: $0) }
}
