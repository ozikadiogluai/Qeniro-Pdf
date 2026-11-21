import SwiftUI
import PDFKit
import UIKit

/// Ana sekme çubuğu.
enum MainTab: Hashable {
    case home, tools, files, starred
}

/// Araçlar sekmesinden veya ana sayfadan başlatılan işler.
enum ToolKind: String, Identifiable, CaseIterable {
    case editPDF, createPDF, merge, split, compress, convert, toWord, toExcel, toPowerPoint, sign, protect, organize, redact, ocr
    var id: String { rawValue }

    var title: String {
        switch self {
        case .editPDF: return String(localized: "PDF Düzenle")
        case .createPDF: return String(localized: "PDF Oluştur")
        case .merge: return String(localized: "Dosyaları Birleştir")
        case .split: return String(localized: "PDF Böl")
        case .compress: return String(localized: "PDF Sıkıştır")
        case .convert: return String(localized: "Dönüştür")
        case .toWord: return String(localized: "PDF'yi Word'e")
        case .toExcel: return String(localized: "PDF'yi Excel'e")
        case .toPowerPoint: return String(localized: "PDF'yi PowerPoint'e")
        case .sign: return String(localized: "Doldur ve İmzala")
        case .protect: return String(localized: "Şifreyle Koru")
        case .organize: return String(localized: "Sayfaları Organize Et")
        case .redact: return String(localized: "PDF'de Sansürle")
        case .ocr: return String(localized: "Tara ve OCR")
        }
    }

    /// Ana sayfadaki kısa ad.
    var shortTitle: String {
        switch self {
        case .merge: return String(localized: "Birleştir")
        case .split: return String(localized: "Böl")
        case .compress: return String(localized: "Sıkıştır")
        case .sign: return String(localized: "İmzala")
        case .protect: return String(localized: "Koruma")
        default: return title
        }
    }

    var icon: String {
        switch self {
        case .editPDF: return "pencil.and.outline"
        case .createPDF: return "doc.badge.plus"
        case .merge: return "rectangle.stack.badge.plus"
        case .split: return "scissors"
        case .compress: return "arrow.down.right.and.arrow.up.left"
        case .convert: return "arrow.left.arrow.right.square"
        case .toWord: return "doc.text"
        case .toExcel: return "tablecells"
        case .toPowerPoint: return "rectangle.on.rectangle.angled"
        case .sign: return "signature"
        case .protect: return "lock.shield"
        case .organize: return "square.grid.2x2"
        case .redact: return "eye.slash"
        case .ocr: return "text.viewfinder"
        }
    }

    var tint: Color {
        switch self {
        case .editPDF: return Theme.accent
        case .createPDF: return Theme.accent
        case .merge: return Theme.blue
        case .split: return Theme.purple
        case .compress: return Theme.accent
        case .convert: return Theme.blue
        case .toWord: return Theme.blue
        case .toExcel: return Theme.green
        case .toPowerPoint: return Theme.orange
        case .sign: return Theme.purple
        case .protect: return Theme.indigo
        case .organize: return Theme.leaf
        case .redact: return Theme.pink
        case .ocr: return Theme.blue
        }
    }

    /// Bu araç birden çok PDF ister mi?
    var multipleFiles: Bool { self == .merge }
}

/// Şifreli bir PDF için şifre isteği.
struct PasswordRequest: Identifiable {
    let id = UUID()
    let data: Data
    let url: URL
    var then: ((DocumentSession) -> Void)?
}

/// Uygulamanın genel durumu: açık belge, sekme, kitaplık, uyarılar.
@MainActor
final class AppModel: ObservableObject {
    @Published var tab: MainTab = .home
    @Published var session: DocumentSession?
    @Published var errorMessage: String?
    @Published var passwordRequest: PasswordRequest?
    @Published var busyMessage: String?
    @Published var shareItem: ShareItem?
    /// Araçlar sekmesinden başlatılan, dosya seçimi bekleyen araç.
    @Published var pendingTool: ToolKind?
    /// Dosya seçildikten sonra seçenekleri gösterilecek araç.
    @Published var toolRun: ToolRun?
    @Published var showCreate = false
    @Published var showScanner = false

    let library = FileLibrary()

    // MARK: - Açma

    /// Bir PDF dosyasını görüntüleyicide açar. `then` açıldıktan sonra (ör. Düzenle sekmesine geçmek için) çağrılır.
    func open(_ url: URL, then: ((DocumentSession) -> Void)? = nil) {
        if let s = session {
            if s.url == url { then?(s); return }
            // Açık belgedeki değişiklikler kaybolmasın diye önce kaydedilir.
            if s.isDirty { _ = s.save() }
            s.close()
            session = nil
        }
        let scoped = url.startAccessingSecurityScopedResource()
        var data: Data?
        var readError: NSError?
        NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &readError) { u in
            data = try? Data(contentsOf: u)
        }
        guard let data, !data.isEmpty else {
            if scoped { url.stopAccessingSecurityScopedResource() }
            errorMessage = String(localized: "\"\(url.lastPathComponent)\" okunamadı. Dosya iCloud'da ise önce indirilmesini bekleyin.")
            return
        }
        guard let doc = PDFDocument(data: data) else {
            if scoped { url.stopAccessingSecurityScopedResource() }
            errorMessage = QPDFError.cannotOpen(url.lastPathComponent).localizedDescription
            return
        }
        if doc.isLocked {
            if scoped { url.stopAccessingSecurityScopedResource() }
            passwordRequest = PasswordRequest(data: data, url: url, then: then)
            return
        }
        present(doc, url: url, password: nil, scoped: scoped, then: then)
    }

    func unlock(_ request: PasswordRequest, password: String) {
        guard let doc = PDFDocument(data: request.data), doc.unlock(withPassword: password) else {
            errorMessage = String(localized: "Şifre yanlış.")
            return
        }
        let scoped = request.url.startAccessingSecurityScopedResource()
        present(doc, url: request.url, password: password, scoped: scoped, then: request.then)
    }

    private func present(_ doc: PDFDocument, url: URL, password: String?, scoped: Bool, then: ((DocumentSession) -> Void)?) {
        let s = DocumentSession(document: doc, url: url, password: password)
        if scoped { s.scopedURL = url }
        s.onSaved = { [weak self] u in self?.library.noteOpened(u) }
        library.noteOpened(url)
        session = s
        if let then {
            // Görüntüleyici ekranı açıldıktan sonra sekmeye/moda geç.
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 350_000_000)
                then(s)
            }
        }
    }

    func open(_ entry: FileEntry) {
        let u = entry.resolvedURL()
        open(u)
    }

    /// Yeni oluşturulan belgeyi uygulamanın Belgeler klasörüne kaydedip açar.
    func saveAndOpen(_ doc: PDFDocument, name: String, then: ((DocumentSession) -> Void)? = nil) {
        let url = DocTools.uniqueDocumentURL(name)
        do {
            try DocTools.write(doc, to: url)
        } catch {
            errorMessage = error.localizedDescription
            return
        }
        open(url, then: then)
    }

    func closeSession() {
        session?.close()
        session = nil
    }

    // MARK: - Tarama

    /// Taranan sayfaları OCR ile aranabilir PDF'ye çevirir, kaydeder ve açar.
    func finishScan(_ images: [UIImage]) {
        guard !images.isEmpty else { return }
        busyMessage = String(localized: "Sayfalar hazırlanıyor ve metin tanınıyor (OCR)…")
        let cgImages = images.compactMap { ImageAnnotation.makeCGImage($0) }
        Task {
            let pagesData: [Data] = await Task.detached(priority: .userInitiated) {
                var out: [Data] = []
                for cg in cgImages {
                    let w = PageRenderer.a4.width
                    let size = CGSize(width: w, height: (w * CGFloat(cg.height) / CGFloat(max(cg.width, 1))).rounded())
                    let lines = (try? PDFOCRService.recognize(cgImage: cg, pageSize: size)) ?? []
                    if let d = PageRenderer.singlePageData(size: size, draw: { ctx in
                        ctx.interpolationQuality = .high
                        ctx.draw(cg, in: CGRect(origin: .zero, size: size))
                        PageRenderer.drawInvisibleText(lines, in: ctx)
                    }) {
                        out.append(d)
                    }
                }
                return out
            }.value
            let doc = PDFDocument()
            for d in pagesData {
                if let p = PageRenderer.page(from: d) { doc.insert(p, at: doc.pageCount) }
            }
            busyMessage = nil
            guard doc.pageCount > 0 else {
                errorMessage = String(localized: "Taranan sayfalar PDF'ye çevrilemedi.")
                return
            }
            let f = DateFormatter()
            f.locale = Fmt.locale
            f.dateFormat = "dd.MM.yyyy HH.mm"
            saveAndOpen(doc, name: String(localized: "Tarama \(f.string(from: Date()))"))
        }
    }

    // MARK: - Araçlar

    /// Araç için seçilen dosyalar geldiğinde: düzenleme türü araçlar belgeyi açar, diğerleri seçenek panelini gösterir.
    func run(_ tool: ToolKind, with urls: [URL]) {
        guard let first = urls.first else { return }
        switch tool {
        case .editPDF:
            open(first) { s in s.activeTab = .edit; s.enterMode(.edit) }
        case .sign:
            open(first) { s in s.activeTab = .sign; s.enterMode(.sign) }
        case .organize:
            open(first) { s in s.showOrganizer = true }
        case .redact:
            open(first) { s in s.tool = .redact }
        case .ocr:
            open(first) { s in s.runOCR(force: false) }
        default:
            toolRun = ToolRun(tool: tool, urls: urls)
        }
    }
}

/// Seçenekleri gösterilecek araç işi.
struct ToolRun: Identifiable {
    let id = UUID()
    let tool: ToolKind
    var urls: [URL]
}
