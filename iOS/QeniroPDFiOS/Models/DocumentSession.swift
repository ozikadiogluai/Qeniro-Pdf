import SwiftUI
import UIKit
import PDFKit

/// Görüntüleyicinin alt sekmeleri.
enum ViewerTab: String, CaseIterable, Identifiable {
    case allTools, edit, convert, sign
    var id: String { rawValue }
    var title: String {
        switch self {
        case .allTools: return String(localized: "Tüm araçlar")
        case .edit: return String(localized: "Düzenle")
        case .convert: return String(localized: "Dönüştür")
        case .sign: return String(localized: "E-imza")
        }
    }
    var icon: String {
        switch self {
        case .allTools: return "square.grid.2x2"
        case .edit: return "pencil"
        case .convert: return "arrow.left.arrow.right"
        case .sign: return "signature"
        }
    }
}

/// Sayfaya dokunma / sürükleme ile çalışan araçlar.
enum ViewerTool: Equatable {
    case select
    case comment
    case draw
    case editText
    case addImage
    case placeSignature(UUID)
    case placeText
    case placeCheck
    case placeDate
    case link
    case redact
    case crop

    var isRectTool: Bool { self == .link || self == .redact || self == .crop }

    var hint: String? {
        switch self {
        case .select: return nil
        case .comment: return String(localized: "Yorum eklemek istediğin yere dokun.")
        case .draw: return String(localized: "Parmağınla veya Apple Pencil ile çiz. Bitince Seç'e dokun.")
        case .editText: return String(localized: "Değiştirmek istediğin yazıya dokun. Kaydedince PDF'teki asıl metin değişir.")
        case .addImage: return String(localized: "Görüntüyü koymak istediğin yere dokun.")
        case .placeSignature: return String(localized: "İmzayı koymak istediğin yere dokun, sonra sürükleyerek konumlandır.")
        case .placeText: return String(localized: "Metin eklemek istediğin yere dokun.")
        case .placeCheck: return String(localized: "Onay işaretini koymak istediğin yere dokun.")
        case .placeDate: return String(localized: "Tarihi koymak istediğin yere dokun.")
        case .link: return String(localized: "Bağlantı olacak alanı parmağınla sürükleyerek çiz.")
        case .redact: return String(localized: "Kaldırılacak alanları sürükleyerek işaretle, sonra Sansürü uygula.")
        case .crop: return String(localized: "Sayfada kalacak alanı sürükleyerek çiz.")
        }
    }
}

/// Satır içi düzenleme kutusunun hedefi.
enum InlineTarget {
    case pdfText(PDFTextItem)
    case newText(pageIndex: Int, topLeft: CGPoint)
    case annotation(PDFAnnotation)
}

/// Yüzen araç çubuğundaki işaretleme türleri.
enum MarkupKind {
    case highlight, underline, strikeOut
    var title: String {
        switch self {
        case .highlight: return String(localized: "Vurgula")
        case .underline: return String(localized: "Altını çiz")
        case .strikeOut: return String(localized: "Üstünü çiz")
        }
    }
    var subtype: PDFAnnotationSubtype {
        switch self {
        case .highlight: return .highlight
        case .underline: return .underline
        case .strikeOut: return .strikeOut
        }
    }
    var color: UIColor {
        switch self {
        case .highlight: return UIColor(red: 0.96, green: 0.77, blue: 0.09, alpha: 0.55)
        case .underline: return UIColor(red: 0.18, green: 0.42, blue: 0.89, alpha: 1)
        case .strikeOut: return UIColor(red: 0.90, green: 0.20, blue: 0.18, alpha: 1)
        }
    }
}

/// Açık bir PDF belgesinin tüm durumu: görünüm, araçlar, geri alma, gerçek metin düzenleme, kaydetme.
@MainActor
final class DocumentSession: ObservableObject, Identifiable {
    let id = UUID()
    @Published var url: URL?
    @Published private(set) var document: PDFDocument
    @Published var isDirty = false
    @Published var currentPageIndex = 0
    @Published var pageCount = 0
    @Published var tool: ViewerTool = .select {
        didSet { if oldValue != tool { toolChanged(from: oldValue) } }
    }
    @Published var activeTab: ViewerTab?
    /// Düzenle veya E-imza modunda üst çubuk ve ipucu bandı değişir.
    @Published var mode: ViewerTab?
    @Published var selectedTextItem: PDFTextItem?
    @Published private(set) var selectedAnnotation: PDFAnnotation?
    @Published var inlineTarget: InlineTarget?
    @Published var textStyle = TextStyle()
    @Published var isSearching = false
    @Published var searchText = ""
    @Published private(set) var searchResults: [PDFSelection] = []
    @Published private(set) var searchIndex = 0
    @Published private(set) var revision = 0
    @Published var busyMessage: String?
    @Published var errorMessage: String?
    @Published var infoMessage: String?
    @Published var inkColor = UIColor(red: 0.90, green: 0.20, blue: 0.18, alpha: 1)
    @Published var showOrganizer = false
    @Published private(set) var canUndo = false
    @Published private(set) var canRedo = false

    /// Bir kullanıcı girdisi bekleyen işlemler (SwiftUI uyarıları ile sorulur).
    @Published var pendingComment: (page: Int, point: CGPoint)?
    @Published var pendingLinkRect: (page: Int, rect: CGRect)?
    @Published var pendingCropRect: (page: Int, rect: CGRect)?

    var pendingImage: UIImage?
    var password: String?
    /// Dosyalar uygulamasından açılan dosyanın güvenlik kapsamı (oturum kapanınca bırakılır).
    var scopedURL: URL?
    var onSaved: ((URL) -> Void)?

    let undoManager = UndoManager()
    let pdfView: PDFView
    private var textEditor: PDFiumEditor?
    private var textItemCache: [Int: [PDFTextItem]] = [:]
    private var tags: [ObjectIdentifier: QTag] = [:]
    private var observers: [NSObjectProtocol] = []
    /// Düzenle/E-imza moduna girildiğindeki geri alma derinliği ("Vazgeç" için).
    private var undoDepth = 0
    private var modeStartDepth = 0

    var displayName: String { url?.lastPathComponent ?? String(localized: "Adsız.pdf") }

    init(document: PDFDocument, url: URL?, password: String? = nil) {
        self.document = document
        self.url = url
        self.password = password
        self.pageCount = document.pageCount
        let v = PDFView(frame: .zero)
        v.document = document
        v.autoScales = true
        v.displayMode = .singlePageContinuous
        v.displayDirection = .vertical
        v.pageShadowsEnabled = true
        v.backgroundColor = .clear
        self.pdfView = v
        undoManager.levelsOfUndo = 60
        undoManager.groupsByEvent = false
        for i in 0..<document.pageCount {
            document.page(at: i)?.annotations.forEach { a in if let t = a.persistedTag { tags[ObjectIdentifier(a)] = t } }
        }
        let nc = NotificationCenter.default
        observers.append(nc.addObserver(forName: .PDFViewPageChanged, object: v, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.syncPage() }
        })
    }

    deinit {
        for o in observers { NotificationCenter.default.removeObserver(o) }
    }

    func close() {
        if let u = scopedURL { u.stopAccessingSecurityScopedResource() }
        scopedURL = nil
    }

    // MARK: - Gezinme

    func syncPage() {
        if let p = pdfView.currentPage { currentPageIndex = max(0, document.index(for: p)) }
        pageCount = document.pageCount
    }

    func goTo(page index: Int) {
        guard let p = document.page(at: max(0, min(index, document.pageCount - 1))) else { return }
        pdfView.go(to: p)
        syncPage()
    }

    var currentPage: PDFPage? { document.page(at: currentPageIndex) }

    // MARK: - Mod ve araçlar

    func enterMode(_ tab: ViewerTab) {
        commitInlineIfNeeded()
        mode = tab
        modeStartDepth = undoDepth
        switch tab {
        case .edit: tool = .editText
        case .sign: tool = .select
        default: break
        }
    }

    /// "Vazgeç": moda girildiğinden beri yapılan değişiklikleri geri alır.
    func cancelMode() {
        cancelInline()
        while undoDepth > modeStartDepth, undoManager.canUndo { undo() }
        exitMode()
    }

    func exitMode() {
        commitInlineIfNeeded()
        mode = nil
        activeTab = nil
        tool = .select
        selectTextItem(nil)
    }

    private func toolChanged(from old: ViewerTool) {
        if old == .editText { commitInlineIfNeeded(); selectTextItem(nil) }
        if tool != .select { select(nil) }
        refreshOverlay()
    }

    /// Sayfa düzenleyiciyi açar; alt panel açıksa önce onu kapatır (aynı anda tek sayfa sunulabilir).
    func openOrganizer() {
        commitInlineIfNeeded()
        if activeTab != nil {
            activeTab = nil
            Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: 450_000_000)
                self?.showOrganizer = true
            }
        } else {
            showOrganizer = true
        }
    }

    func refreshOverlay() {
        NotificationCenter.default.post(name: .qeniroOverlayNeedsRefresh, object: self)
    }

    // MARK: - Geri al / yinele

    private func updateUndoState() {
        canUndo = undoManager.canUndo
        canRedo = undoManager.canRedo
    }

    /// Tüm değişiklikler bu yoldan geri alma yığınına kaydedilir (derinlik sayacı için).
    /// Her kullanıcı işlemi ayrı bir geri alma grubudur (groupsByEvent kapalı); geri alma veya
    /// yineleme sırasında yapılan kayıtlar UndoManager'ın kendi açtığı gruba gider.
    func registerUndo(_ name: String, _ handler: @escaping (DocumentSession) -> Void) {
        let manual = !undoManager.isUndoing && !undoManager.isRedoing && undoManager.groupingLevel == 0
        if manual { undoManager.beginUndoGrouping() }
        undoManager.registerUndo(withTarget: self) { s in
            MainActor.assumeIsolated { handler(s) }
        }
        undoManager.setActionName(name)
        if manual {
            undoManager.endUndoGrouping()
            undoDepth += 1
        }
        isDirty = true
        revision += 1
        Task { @MainActor [weak self] in self?.updateUndoState() }
    }

    func undo() {
        commitInlineIfNeeded()
        guard undoManager.canUndo else { return }
        undoManager.undo()
        undoDepth = max(0, undoDepth - 1)
        textItemCache = [:]
        textEditor = nil
        updateUndoState()
        refreshOverlay()
    }

    func redo() {
        guard undoManager.canRedo else { return }
        undoManager.redo()
        undoDepth += 1
        textItemCache = [:]
        textEditor = nil
        updateUndoState()
        refreshOverlay()
    }

    // MARK: - Arama

    func search() {
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { clearSearch(); return }
        searchResults = document.findString(q, withOptions: [.caseInsensitive, .diacriticInsensitive])
        searchIndex = 0
        for r in searchResults { r.color = UIColor.systemYellow.withAlphaComponent(0.55) }
        pdfView.highlightedSelections = searchResults
        showSearchResult()
    }

    func nextResult() {
        guard !searchResults.isEmpty else { return }
        searchIndex = (searchIndex + 1) % searchResults.count
        showSearchResult()
    }

    func previousResult() {
        guard !searchResults.isEmpty else { return }
        searchIndex = (searchIndex - 1 + searchResults.count) % searchResults.count
        showSearchResult()
    }

    private func showSearchResult() {
        guard searchIndex < searchResults.count else { return }
        let sel = searchResults[searchIndex]
        pdfView.setCurrentSelection(sel, animate: true)
        pdfView.go(to: sel)
        syncPage()
    }

    func clearSearch() {
        searchResults = []
        searchIndex = 0
        pdfView.highlightedSelections = nil
        pdfView.clearSelection()
    }

    // MARK: - Açıklamalar

    func tag(of a: PDFAnnotation) -> QTag? {
        tags[ObjectIdentifier(a)] ?? a.persistedTag
    }

    private func setTag(_ a: PDFAnnotation, _ t: QTag) {
        tags[ObjectIdentifier(a)] = t
        if !(a is ImageAnnotation) { a.setValue(t.rawValue, forAnnotationKey: QTag.key) }
    }

    func isMovable(_ a: PDFAnnotation) -> Bool { tag(of: a)?.isMovable ?? false }

    func select(_ a: PDFAnnotation?) {
        selectedAnnotation = a
        refreshOverlay()
    }

    func changed(_ page: PDFPage?) {
        revision += 1
        // PDFKit açıklama özelliklerindeki değişiklikleri kendisi yeniden çizer.
        if page != nil { pdfView.setNeedsDisplay() }
        refreshOverlay()
    }

    func add(_ a: PDFAnnotation, to page: PDFPage, tag t: QTag?, name: String = String(localized: "Ekle")) {
        if let t { setTag(a, t) }
        page.addAnnotation(a)
        registerUndo(name) { s in s.remove(a, name: name) }
        changed(page)
    }

    func remove(_ a: PDFAnnotation, name: String = String(localized: "Sil")) {
        guard let page = a.page else { return }
        page.removeAnnotation(a)
        if selectedAnnotation === a { selectedAnnotation = nil }
        let t = tag(of: a)
        registerUndo(name) { s in s.add(a, to: page, tag: t, name: name) }
        changed(page)
    }

    func deleteSelected() {
        if let a = selectedAnnotation { remove(a) }
    }

    func setBounds(_ a: PDFAnnotation, to r: CGRect, from old: CGRect, name: String = String(localized: "Taşı")) {
        a.bounds = r
        registerUndo(name) { s in s.setBounds(a, to: old, from: r, name: name) }
        changed(a.page)
    }

    /// Sürükleme sırasında canlı güncelleme (geri alma kaydı yok).
    func liveMove(_ a: PDFAnnotation, to r: CGRect) {
        a.bounds = r
        pdfView.setNeedsDisplay()
        refreshOverlay()
    }

    /// Seçili öğeyi büyütür / küçültür (imza ve görseller için).
    func scaleSelected(_ factor: CGFloat) {
        guard let a = selectedAnnotation else { return }
        let old = a.bounds
        var r = old
        let w = max(12, old.width * factor), h = max(8, old.height * factor)
        r = CGRect(x: old.midX - w / 2, y: old.midY - h / 2, width: w, height: h)
        if a.isFreeText, let f = a.font {
            a.font = f.withSize(max(4, f.pointSize * factor))
        }
        setBounds(a, to: r, from: old, name: String(localized: "Boyutlandır"))
    }

    func setContents(_ text: String, of a: PDFAnnotation) {
        let old = a.contents ?? ""
        guard old != text else { return }
        a.contents = text
        if a.isFreeText { fitFreeText(a) }
        registerUndo(String(localized: "Metni değiştir")) { s in s.setContents(old, of: a) }
        changed(a.page)
    }

    func fitFreeText(_ a: PDFAnnotation) {
        guard a.isFreeText, let font = a.font else { return }
        let text = (a.contents ?? "").isEmpty ? " " : (a.contents ?? " ")
        let size = (text as NSString).size(withAttributes: [.font: font])
        var r = a.bounds
        let top = r.maxY
        r.size.width = ceil(size.width) + 10
        r.size.height = ceil(size.height) + 6
        r.origin.y = top - r.size.height
        a.bounds = r
    }

    func makeFreeText(_ text: String, topLeft p: CGPoint, style: TextStyle) -> PDFAnnotation {
        let font = style.makeFont()
        let size = (text as NSString).size(withAttributes: [.font: font])
        let w = ceil(size.width) + 10, h = ceil(size.height) + 6
        let a = PDFAnnotation(bounds: CGRect(x: p.x, y: p.y - h, width: w, height: h), forType: .freeText, withProperties: nil)
        a.contents = text
        a.font = font
        a.fontColor = style.uiColor
        a.color = .clear
        let b = PDFBorder(); b.lineWidth = 0
        a.border = b
        return a
    }

    private func fitRect(for size: CGSize, maxSide: CGFloat, center p: CGPoint) -> CGRect {
        let w0 = max(size.width, 1), h0 = max(size.height, 1)
        let s = min(maxSide / w0, maxSide / h0, 1.5)
        let w = w0 * s, h = h0 * s
        return CGRect(x: p.x - w / 2, y: p.y - h / 2, width: w, height: h)
    }

    /// Dokunulan yere seçili aracın öğesini koyar.
    func place(at p: CGPoint, on page: PDFPage) {
        let idx = document.index(for: page)
        switch tool {
        case .comment:
            pendingComment = (idx, p)
        case .addImage:
            guard let img = pendingImage else { tool = .select; return }
            let a = ImageAnnotation(bounds: fitRect(for: img.size, maxSide: 200, center: p), image: img, kind: .image)
            add(a, to: page, tag: .image, name: String(localized: "Görüntü ekle"))
            pendingImage = nil
            tool = .select
            select(a)
        case .placeSignature(let id):
            guard let img = SignatureStore.shared.image(for: id) else { tool = .select; return }
            let isInitials = SignatureStore.shared.signatures.first { $0.id == id }?.isInitials == true
            let a = ImageAnnotation(bounds: fitRect(for: img.size, maxSide: isInitials ? 70 : 150, center: p),
                                    image: img, kind: isInitials ? .initials : .signature)
            add(a, to: page, tag: a.kind, name: String(localized: "İmza ekle"))
            tool = .select
            select(a)
        case .placeText:
            var st = textStyle
            st.family = "Helvetica"
            let a = makeFreeText(String(localized: "Metin"), topLeft: p, style: st)
            add(a, to: page, tag: .text, name: String(localized: "Metin ekle"))
            tool = .select
            select(a)
            inlineTarget = .annotation(a)
        case .placeCheck:
            let img = Self.symbolImage("checkmark", pointSize: 64)
            let a = ImageAnnotation(bounds: fitRect(for: img.size, maxSide: 16, center: p), image: img, kind: .check)
            add(a, to: page, tag: .check, name: String(localized: "Onay ekle"))
            select(a)
        case .placeDate:
            var st = textStyle
            st.family = "Helvetica"; st.size = 11
            let a = makeFreeText(Fmt.shortDate(), topLeft: CGPoint(x: p.x, y: p.y + 8), style: st)
            add(a, to: page, tag: .date, name: String(localized: "Tarih ekle"))
            tool = .select
            select(a)
        case .editText:
            if let item = textItem(at: p, pageIndex: idx) {
                selectTextItem(item)
                inlineTarget = .pdfText(item)
            } else {
                selectTextItem(nil)
                inlineTarget = .newText(pageIndex: idx, topLeft: p)
            }
        case .select:
            let hit = page.annotations.last { a in
                guard tag(of: a) != nil else { return false }
                return a.bounds.insetBy(dx: -6, dy: -6).contains(p)
            }
            if let hit, hit === selectedAnnotation, hit.isFreeText {
                inlineTarget = .annotation(hit)
            } else if let hit, hit.subtypeName == "Text" {
                select(hit)
                pendingComment = (idx, p)
            } else {
                select(hit)
            }
        default:
            break
        }
        refreshOverlay()
    }

    func addComment(_ text: String, page index: Int, at p: CGPoint) {
        guard let page = document.page(at: index) else { return }
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let existing = selectedAnnotation, existing.subtypeName == "Text", existing.page === page {
            if clean.isEmpty { remove(existing) } else { setContents(clean, of: existing) }
            return
        }
        guard !clean.isEmpty else { return }
        let a = PDFAnnotation(bounds: CGRect(x: p.x - 10, y: p.y - 10, width: 22, height: 22), forType: .text, withProperties: nil)
        a.contents = clean
        a.color = UIColor.systemOrange
        a.iconType = .comment
        a.userName = UIDevice.current.name
        add(a, to: page, tag: .note, name: String(localized: "Yorum"))
        tool = .select
    }

    /// Sürüklenen dikdörtgene göre bağlantı, sansür veya kırpma.
    func placeRect(_ r: CGRect, on page: PDFPage) {
        let idx = document.index(for: page)
        guard r.width > 4, r.height > 4 else { return }
        switch tool {
        case .link: pendingLinkRect = (idx, r)
        case .crop: pendingCropRect = (idx, r)
        case .redact: addRedaction(r, on: page)
        default: break
        }
    }

    func addLink(_ raw: String, page index: Int, rect r: CGRect) {
        guard let page = document.page(at: index) else { return }
        var link = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !link.isEmpty else { return }
        let a = PDFAnnotation(bounds: r, forType: .link, withProperties: nil)
        if let n = Int(link), let target = document.page(at: n - 1) {
            let top = target.bounds(for: .cropBox).maxY
            a.action = PDFActionGoTo(destination: PDFDestination(page: target, at: CGPoint(x: 0, y: top)))
        } else {
            if !link.contains("://") { link = "https://" + link }
            guard let u = URL(string: link) else { errorMessage = String(localized: "Geçersiz bağlantı adresi."); return }
            a.url = u
        }
        let b = PDFBorder(); b.lineWidth = 0
        a.border = b
        add(a, to: page, tag: .link, name: String(localized: "Bağlantı ekle"))
        tool = .select
    }

    func addRedaction(_ r: CGRect, on page: PDFPage) {
        let a = PDFAnnotation(bounds: r, forType: .square, withProperties: nil)
        a.color = UIColor.red
        a.interiorColor = UIColor.black.withAlphaComponent(0.85)
        let b = PDFBorder(); b.lineWidth = 1
        a.border = b
        add(a, to: page, tag: .redact, name: String(localized: "Sansür işareti"))
    }

    var redactionMarkCount: Int {
        var n = 0
        for i in 0..<document.pageCount {
            n += document.page(at: i)?.annotations.filter { tag(of: $0) == .redact }.count ?? 0
        }
        return n
    }

    static func symbolImage(_ name: String, pointSize: CGFloat) -> UIImage {
        let cfg = UIImage.SymbolConfiguration(pointSize: pointSize, weight: .bold)
        let sym = UIImage(systemName: name, withConfiguration: cfg)?.withTintColor(.black, renderingMode: .alwaysOriginal)
            ?? UIImage()
        let format = UIGraphicsImageRendererFormat()
        format.opaque = false
        format.scale = 2
        return UIGraphicsImageRenderer(size: sym.size, format: format).image { _ in sym.draw(at: .zero) }
    }

    // MARK: - İşaretleme ve çizim

    func applyMarkup(_ kind: MarkupKind) {
        guard let sel = pdfView.currentSelection, let str = sel.string,
              !str.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            infoMessage = String(localized: "Önce metni basılı tutarak seçin, sonra \(kind.title) düğmesine dokunun.")
            return
        }
        var count = 0
        for line in sel.selectionsByLine() {
            for page in line.pages {
                let r = line.bounds(for: page)
                guard r.width > 0.5, r.height > 0.5 else { continue }
                let a = PDFAnnotation(bounds: r, forType: kind.subtype, withProperties: nil)
                a.color = kind.color
                a.quadrilateralPoints = [
                    NSValue(cgPoint: CGPoint(x: 0, y: r.height)), NSValue(cgPoint: CGPoint(x: r.width, y: r.height)),
                    NSValue(cgPoint: CGPoint(x: 0, y: 0)), NSValue(cgPoint: CGPoint(x: r.width, y: 0))
                ]
                add(a, to: page, tag: .markup, name: kind.title)
                count += 1
            }
        }
        pdfView.clearSelection()
        _ = count
    }

    /// Serbest çizim (ink) açıklaması ekler. Noktalar sayfa koordinatlarındadır.
    func addInk(_ points: [CGPoint], on page: PDFPage, lineWidth: CGFloat = 2) {
        guard points.count > 1 else { return }
        var minX = CGFloat.greatestFiniteMagnitude, minY = CGFloat.greatestFiniteMagnitude
        var maxX = -CGFloat.greatestFiniteMagnitude, maxY = -CGFloat.greatestFiniteMagnitude
        for p in points {
            minX = min(minX, p.x); minY = min(minY, p.y)
            maxX = max(maxX, p.x); maxY = max(maxY, p.y)
        }
        let b = CGRect(x: minX, y: minY, width: max(maxX - minX, 1), height: max(maxY - minY, 1))
            .insetBy(dx: -lineWidth * 2, dy: -lineWidth * 2)
        // Yollar açıklama uzayındadır (sınır kutusunun köşesine göre).
        let path = UIBezierPath()
        path.move(to: CGPoint(x: points[0].x - b.minX, y: points[0].y - b.minY))
        for p in points.dropFirst() { path.addLine(to: CGPoint(x: p.x - b.minX, y: p.y - b.minY)) }
        path.lineWidth = lineWidth
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        let a = PDFAnnotation(bounds: b, forType: .ink, withProperties: nil)
        a.add(path)
        let border = PDFBorder()
        border.lineWidth = lineWidth
        a.border = border
        a.color = inkColor
        add(a, to: page, tag: .ink, name: String(localized: "Çiz"))
    }

    // MARK: - Sayfa işlemleri

    private func structureChanged() {
        pageCount = document.pageCount
        pdfView.layoutDocumentView()
        textItemCache = [:]
        textEditor = nil
        syncPage()
        revision += 1
        refreshOverlay()
    }

    func replacePage(at i: Int, with newPage: PDFPage, name: String) {
        guard let old = document.page(at: i) else { return }
        if let sel = selectedAnnotation, sel.page === old { selectedAnnotation = nil }
        document.removePage(at: i)
        document.insert(newPage, at: i)
        registerTags(of: newPage)
        structureChanged()
        registerUndo(name) { s in s.replacePage(at: i, with: old, name: name) }
    }

    private func registerTags(of page: PDFPage) {
        for a in page.annotations { if let t = a.persistedTag { tags[ObjectIdentifier(a)] = t } }
    }

    func movePage(from: Int, to: Int) {
        guard from != to, from >= 0, from < document.pageCount, let p = document.page(at: from) else { return }
        document.removePage(at: from)
        let dest = max(0, min(to, document.pageCount))
        document.insert(p, at: dest)
        structureChanged()
        registerUndo(String(localized: "Sayfayı taşı")) { s in s.movePage(from: dest, to: from) }
    }

    func rotate(pages indices: [Int], by degrees: Int) {
        for i in indices {
            guard let p = document.page(at: i) else { continue }
            p.rotation = ((p.rotation + degrees) % 360 + 360) % 360
        }
        structureChanged()
        registerUndo(String(localized: "Döndür")) { s in s.rotate(pages: indices, by: -degrees) }
    }

    func rotateCurrent(by degrees: Int) { rotate(pages: [currentPageIndex], by: degrees) }

    func deletePages(_ indices: [Int]) {
        let sorted = Array(Set(indices)).sorted()
        guard !sorted.isEmpty else { return }
        guard sorted.count < document.pageCount else {
            errorMessage = String(localized: "Belgede en az bir sayfa kalmalı.")
            return
        }
        var removed: [(Int, PDFPage)] = []
        for i in sorted.reversed() {
            if let p = document.page(at: i) {
                removed.append((i, p))
                document.removePage(at: i)
            }
        }
        structureChanged()
        registerUndo(String(localized: "Sayfa sil")) { s in s.restorePages(removed) }
    }

    private func restorePages(_ items: [(Int, PDFPage)]) {
        for (i, p) in items.reversed() { document.insert(p, at: min(i, document.pageCount)) }
        structureChanged()
        let indices = items.map { $0.0 }
        registerUndo(String(localized: "Sayfa sil")) { s in s.deletePages(indices) }
    }

    func insertPages(_ pages: [PDFPage], at index: Int, name: String = String(localized: "Sayfa ekle")) {
        guard !pages.isEmpty else { return }
        let start = max(0, min(index, document.pageCount))
        for (k, p) in pages.enumerated() { document.insert(p, at: start + k) }
        structureChanged()
        let indices = Array(start..<(start + pages.count))
        registerUndo(name) { s in s.removeInserted(indices, name: name) }
    }

    private func removeInserted(_ indices: [Int], name: String) {
        var removed: [(Int, PDFPage)] = []
        for i in indices.sorted().reversed() {
            if let p = document.page(at: i) { removed.append((i, p)); document.removePage(at: i) }
        }
        structureChanged()
        registerUndo(name) { s in
            s.insertPages(removed.sorted { $0.0 < $1.0 }.map { $0.1 }, at: indices.min() ?? 0, name: name)
        }
    }

    func insertBlankPage(after index: Int) {
        let ref = document.page(at: max(0, min(index, document.pageCount - 1)))
        let size = ref?.bounds(for: .mediaBox).size ?? PageRenderer.a4
        if let blank = PageRenderer.blankPage(size: size) { insertPages([blank], at: index + 1) }
    }

    /// Başka PDF'lerin sayfalarını belgenin sonuna ekler (Dosyaları birleştir).
    func appendPDFs(_ urls: [URL]) {
        var pages: [PDFPage] = []
        do {
            for url in urls {
                let other = try SecurityScope.access(url) { try DocTools.open(url) }
                for i in 0..<other.pageCount {
                    if let p = other.page(at: i)?.copy() as? PDFPage { pages.append(p) }
                }
            }
        } catch {
            errorMessage = error.localizedDescription
            return
        }
        insertPages(pages, at: document.pageCount, name: String(localized: "Dosyaları birleştir"))
        infoMessage = String(localized: "\(pages.count) sayfa belgenin sonuna eklendi.")
    }

    func cropPages(_ indices: [Int], to r: CGRect) {
        setCropBoxes(indices.map { ($0, r) })
        tool = .select
    }

    private func setCropBoxes(_ items: [(Int, CGRect)]) {
        var old: [(Int, CGRect)] = []
        for (i, r) in items {
            guard let p = document.page(at: i) else { continue }
            let media = p.bounds(for: .mediaBox)
            let c = r.intersection(media)
            guard !c.isNull, c.width > 4, c.height > 4 else { continue }
            old.append((i, p.bounds(for: .cropBox)))
            p.setBounds(c, for: .cropBox)
        }
        guard !old.isEmpty else { return }
        structureChanged()
        registerUndo(String(localized: "Kırp")) { s in s.setCropBoxes(old) }
    }

    // MARK: - Uygula / Sansür / OCR

    /// İmza, metin, onay ve tarih gibi eklenen öğeleri sayfaya kalıcı olarak gömer.
    func applyAnnotations() -> Int {
        commitInlineIfNeeded()
        var count = 0
        for i in 0..<document.pageCount {
            guard let page = document.page(at: i) else { continue }
            let anns = page.annotations
            let flat = anns.filter { tag(of: $0)?.flattensOnApply ?? false }
            guard !flat.isEmpty else { continue }
            let keep = anns.filter { a in !flat.contains { $0 === a } }
            if let np = PageRenderer.rebuild(page: page, flatten: flat, keep: keep) {
                replacePage(at: i, with: np, name: String(localized: "Uygula"))
                count += 1
            }
        }
        selectedAnnotation = nil
        return count
    }

    /// İşaretli alanları sayfadan gerçekten kaldırır: sayfa görüntüye çevrilir, alanlar siyahla
    /// boyanır ve kalan metin OCR ile görünmez katman olarak geri eklenir.
    func applyRedactions(restoreText: Bool = true) {
        var count = 0
        busyMessage = String(localized: "Sansür uygulanıyor…")
        for i in 0..<document.pageCount {
            guard let page = document.page(at: i) else { continue }
            let marks = page.annotations.filter { tag(of: $0) == .redact }
            guard !marks.isEmpty else { continue }
            let rects = marks.map { $0.bounds }
            let others = page.annotations.filter { tag(of: $0) != .redact }
            let images = others.filter { $0 is ImageAnnotation }
            guard let img = PageRenderer.renderImage(page: page, dpi: 200, includeAnnotations: images, overlay: { ctx in
                ctx.setFillColor(CGColor(gray: 0, alpha: 1))
                for r in rects { ctx.fill(r) }
            }) else { continue }
            let box = page.bounds(for: .mediaBox)
            var lines: [OCRLine] = []
            if restoreText { lines = (try? PDFOCRService.recognize(cgImage: img, pageSize: box.size)) ?? [] }
            let keep = others.filter { a in !(a is ImageAnnotation) && !rects.contains { $0.intersects(a.bounds) } }
            let shifted = rects.map { $0.offsetBy(dx: -box.minX, dy: -box.minY) }
            let safeLines = lines.filter { l in !shifted.contains { $0.intersects(l.rect) } }
            if let np = PageRenderer.rebuild(page: page, contentImage: img, keep: keep, extra: { ctx in
                PageRenderer.drawInvisibleText(safeLines, in: ctx)
            }) {
                replacePage(at: i, with: np, name: String(localized: "Sansürle"))
                count += 1
            }
        }
        busyMessage = nil
        if count == 0 {
            infoMessage = String(localized: "Önce kaldırılacak alanları sürükleyerek işaretleyin.")
        } else {
            tool = .select
            infoMessage = String(localized: "\(count) sayfada sansür uygulandı. Kaydetmeyi unutmayın.")
        }
    }

    /// Taranmış sayfalara aranabilir metin katmanı ekler.
    func runOCR(force: Bool = false) {
        guard let data = currentData() else { return }
        busyMessage = String(localized: "Metin tanınıyor (OCR)…")
        Task {
            let result: [[OCRLine]?]
            do {
                result = try await Task.detached(priority: .userInitiated) {
                    try PDFOCRService.recognizeAll(data: data, skipPagesWithText: !force)
                }.value
            } catch {
                busyMessage = nil
                errorMessage = String(localized: "OCR başarısız: \(error.localizedDescription)")
                return
            }
            var count = 0
            for (i, lines) in result.enumerated() {
                guard let lines, !lines.isEmpty, let page = document.page(at: i) else { continue }
                if let np = PageRenderer.rebuild(page: page, keep: page.annotations, extra: { ctx in
                    PageRenderer.drawInvisibleText(lines, in: ctx)
                }) {
                    replacePage(at: i, with: np, name: "OCR")
                    count += 1
                }
            }
            busyMessage = nil
            infoMessage = count > 0 ? String(localized: "\(count) sayfaya aranabilir metin katmanı eklendi. Kaydetmeyi unutmayın.")
                                    : String(localized: "Tüm sayfalarda zaten seçilebilir metin var.")
        }
    }

    // MARK: - Gerçek metin düzenleme (PDFium)

    /// PDFium'a verilecek belge baytları. Görsel/imza açıklamaları (özel çizim) PDFKit tarafından
    /// dosyaya düzgün yazılamadığı için geçici olarak çıkarılır; belge değişince yeni sayfalara taşınır.
    func pdfiumSourceData() -> Data? {
        var removed: [(PDFPage, PDFAnnotation)] = []
        for i in 0..<document.pageCount {
            guard let p = document.page(at: i) else { continue }
            for a in p.annotations where a is ImageAnnotation {
                removed.append((p, a))
                p.removeAnnotation(a)
            }
        }
        let data = document.dataRepresentation()
        for (p, a) in removed { p.addAnnotation(a) }
        return data
    }

    func textItems(onPage index: Int) -> [PDFTextItem] {
        if let cached = textItemCache[index] { return cached }
        if textEditor == nil, PDFiumSupport.isAvailable, let data = pdfiumSourceData() {
            textEditor = try? PDFiumEditor(data: data, password: password)
        }
        let items = (try? textEditor?.textItems(pageIndex: index)) ?? []
        textItemCache[index] = items
        return items
    }

    func textItem(at point: CGPoint, pageIndex: Int) -> PDFTextItem? {
        let hits = textItems(onPage: pageIndex).filter { $0.bounds.insetBy(dx: -3, dy: -3).contains(point) }
        return hits.min { $0.bounds.width * $0.bounds.height < $1.bounds.width * $1.bounds.height }
    }

    /// Bir metin satırını seçer ve panelin metin özelliklerini ona göre doldurur.
    func selectTextItem(_ item: PDFTextItem?) {
        selectedTextItem = item
        if let item {
            if selectedAnnotation != nil { selectedAnnotation = nil }
            var s = textStyle
            s.family = item.familyName
            s.size = max(1, (item.visualSize * 2).rounded() / 2)
            s.bold = item.bold
            s.italic = item.italic
            s.underline = false
            s.color = Color(uiColor: item.color.withAlphaComponent(1))
            textStyle = s
        }
        refreshOverlay()
    }

    /// Paneldeki biçim değişikliğini seçili gerçek metne (veya seçili metin kutusuna) uygular.
    func updateStyle(_ change: (inout TextStyle) -> Void) {
        let before = textStyle
        var s = textStyle
        change(&s)
        textStyle = s
        if let item = selectedTextItem {
            var st = TextEditStyle()
            if s.family != before.family { st.family = s.family }
            if s.bold != before.bold { st.bold = s.bold }
            if s.italic != before.italic { st.italic = s.italic }
            if s.size != before.size { st.visualSize = s.size }
            if s.color != before.color { st.color = s.uiColor }
            st.underline = s.underline && !before.underline
            var text = item.text
            if case .pdfText(let editing)? = inlineTarget, editing == item, let pending = pendingInlineText { text = pending }
            inlineTarget = nil
            commitTextEdit(item, newText: text, style: st)
            return
        }
        if let a = selectedAnnotation, a.isFreeText {
            let oldFont = a.font, oldColor = a.fontColor
            a.font = s.makeFont()
            a.fontColor = s.uiColor
            fitFreeText(a)
            registerUndo(String(localized: "Biçim")) { sess in
                a.font = oldFont; a.fontColor = oldColor
                sess.fitFreeText(a); sess.changed(a.page)
            }
            changed(a.page)
        }
    }

    /// Satır içi kutudaki güncel metin (kutu açıkken görünüm tarafından güncellenir).
    var pendingInlineText: String?

    func commitInlineIfNeeded() {
        NotificationCenter.default.post(name: .qeniroCommitInline, object: self)
    }

    func cancelInline() {
        pendingInlineText = nil
        inlineTarget = nil
        refreshOverlay()
    }

    /// Satır içi düzenleme kutusu kapanınca çağrılır.
    func finishInline(_ text: String) {
        guard let target = inlineTarget else { return }
        inlineTarget = nil
        pendingInlineText = nil
        switch target {
        case .pdfText(let item):
            commitTextEdit(item, newText: text)
        case .newText(let idx, let topLeft):
            if !text.trimmingCharacters(in: .whitespaces).isEmpty, let page = document.page(at: idx) {
                insertNewText(text, topLeft: topLeft, on: page)
            }
        case .annotation(let a):
            if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                remove(a)
            } else {
                setContents(text, of: a)
            }
        }
        refreshOverlay()
    }

    /// Belgeyi PDFium ile düzenler, sonucu yeni PDFDocument olarak yükler (geri alınabilir).
    @discardableResult
    private func runPDFiumEdit(_ name: String, _ body: (PDFiumEditor) throws -> Void) -> Bool {
        do {
            guard let data = pdfiumSourceData() else { throw QPDFError.message(String(localized: "Belge hazırlanamadı.")) }
            let editor = try PDFiumEditor(data: data, password: password)
            try body(editor)
            let out = try editor.save()
            guard let newDoc = PDFDocument(data: out) else { throw QPDFError.message(String(localized: "Düzenlenen belge açılamadı.")) }
            if newDoc.isLocked, let pw = password { _ = newDoc.unlock(withPassword: pw) }
            guard newDoc.pageCount == document.pageCount else {
                throw QPDFError.message(String(localized: "Sayfa sayısı beklenmedik şekilde değişti; işlem iptal edildi."))
            }
            replaceDocument(with: newDoc, name: name)
            return true
        } catch {
            errorMessage = String(localized: "\(name) yapılamadı: \(error.localizedDescription)")
            return false
        }
    }

    /// Belgenin tamamını başka bir PDFDocument ile değiştirir; görünüm konumu ve yakınlaştırma korunur.
    func replaceDocument(with newDoc: PDFDocument, name: String) {
        let old = document
        for i in 0..<min(old.pageCount, newDoc.pageCount) {
            guard let op = old.page(at: i), let np = newDoc.page(at: i) else { continue }
            for a in op.annotations where a is ImageAnnotation {
                op.removeAnnotation(a)
                np.addAnnotation(a)
            }
        }
        let auto = pdfView.autoScales
        let scale = pdfView.scaleFactor
        let dest = pdfView.currentDestination
        let destIndex = dest?.page.map { old.index(for: $0) } ?? currentPageIndex
        let destPoint = dest?.point
        selectedAnnotation = nil
        clearSearch()
        document = newDoc
        pdfView.document = newDoc
        pdfView.autoScales = auto
        if !auto { pdfView.scaleFactor = scale }
        if destIndex >= 0, destIndex != NSNotFound, let p = newDoc.page(at: destIndex) {
            if let destPoint {
                pdfView.go(to: PDFDestination(page: p, at: destPoint))
            } else {
                pdfView.go(to: p)
            }
        }
        for i in 0..<newDoc.pageCount { if let p = newDoc.page(at: i) { registerTags(of: p) } }
        textEditor = nil
        textItemCache = [:]
        pageCount = newDoc.pageCount
        syncPage()
        registerUndo(name) { s in s.replaceDocument(with: old, name: name) }
        refreshOverlay()
    }

    /// Satır içi düzenlemeyi PDF'e yazar: aynı nesnede değiştirir ya da benzer yazı tipiyle yeniden yazar.
    func commitTextEdit(_ item: PDFTextItem, newText: String, style: TextEditStyle? = nil) {
        guard style != nil || newText != item.text else { return }
        let deleting = newText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        var result: TextEditResult?
        let ok = runPDFiumEdit(deleting ? String(localized: "Metni sil") : String(localized: "Metni düzenle")) { editor in
            result = try editor.replaceText(item, with: newText, style: style)
        }
        guard ok, let result else { return }
        if deleting {
            selectedTextItem = nil
        } else {
            let box = result.bounds
            let candidates = textItems(onPage: item.pageIndex).filter { $0.bounds.intersects(box.insetBy(dx: 0.5, dy: 0.5)) }
            selectedTextItem = candidates.max { a, b in
                Self.overlapArea(a.bounds, box) < Self.overlapArea(b.bounds, box)
            }
        }
        if result.substitutedFont {
            infoMessage = String(localized: "Özgün yazı tipi yeni karakterleri içermediği için bu satır benzer bir sistem yazı tipiyle yeniden yazıldı (metin PDF içinde gerçekten değişti).")
        }
        refreshOverlay()
    }

    private static func overlapArea(_ a: CGRect, _ b: CGRect) -> CGFloat {
        let r = a.intersection(b)
        return r.isNull ? 0 : r.width * r.height
    }

    /// Boş bir yere dokunup yazılan metni gerçek metin nesnesi olarak ekler.
    func insertNewText(_ text: String, topLeft: CGPoint, on page: PDFPage) {
        let idx = document.index(for: page)
        guard idx != NSNotFound, idx >= 0 else { return }
        let style = textStyle
        let size = style.size
        let rotation = page.rotation
        let angle = CGFloat(rotation) * .pi / 180
        let ascent = size * 0.8
        let baseline = CGPoint(x: topLeft.x + sin(angle) * ascent, y: topLeft.y - cos(angle) * ascent)
        var box = CGRect.zero
        let ok = runPDFiumEdit(String(localized: "Metin ekle")) { editor in
            box = try editor.insertText(text, pageIndex: idx, baseline: baseline, family: style.family,
                                        bold: style.bold, italic: style.italic, size: size,
                                        color: style.uiColor, rotation: rotation, underline: style.underline)
        }
        if ok {
            selectedTextItem = textItems(onPage: idx).first { $0.bounds.intersects(box) }
            refreshOverlay()
        }
    }

    func deleteSelectedTextItem() {
        guard let item = selectedTextItem else { return }
        inlineTarget = nil
        commitTextEdit(item, newText: "")
    }

    func applyHeaderFooter(header: String, footer: String, numberFormat: String?,
                           position: PDFiumNumberPosition, size: CGFloat, color: UIColor, margin: CGFloat) {
        let date = Fmt.shortDate()
        runPDFiumEdit(String(localized: "Üstbilgi ve altbilgi")) { editor in
            try editor.addHeaderFooter(header: header, footer: footer, numberFormat: numberFormat,
                                       numberPosition: position, size: size, color: color, margin: margin, date: date)
        }
    }

    func applyWatermark(text: String, size: CGFloat, color: UIColor, opacity: CGFloat, angle: CGFloat, bold: Bool) {
        runPDFiumEdit(String(localized: "Filigran")) { editor in
            try editor.addWatermark(text, size: size, color: color, opacity: opacity, angle: angle, bold: bold)
        }
    }

    // MARK: - Kaydetme

    /// Görsel/imza açıklamaları düzleştirilmiş, yazılmaya hazır belge.
    func documentForWriting() -> PDFDocument {
        var hasImages = false
        for i in 0..<document.pageCount where document.page(at: i)?.annotations.contains(where: { $0 is ImageAnnotation }) == true {
            hasImages = true
            break
        }
        guard hasImages else { return document }
        let out = PDFDocument()
        for i in 0..<document.pageCount {
            guard let p = document.page(at: i) else { continue }
            let imgs = p.annotations.filter { $0 is ImageAnnotation }
            if imgs.isEmpty {
                if let c = p.copy() as? PDFPage { out.insert(c, at: out.pageCount) }
            } else if let np = PageRenderer.rebuild(page: p, flatten: imgs, keep: p.annotations.filter { !($0 is ImageAnnotation) }) {
                out.insert(np, at: out.pageCount)
            }
        }
        if let attrs = document.documentAttributes { out.documentAttributes = attrs }
        return out
    }

    /// Kaydedilecek baytlar (belge şifreliyse aynı şifreyle).
    func currentData() -> Data? {
        let output = documentForWriting()
        if let pw = password, !pw.isEmpty {
            let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("qeniro-\(UUID().uuidString).pdf")
            defer { try? FileManager.default.removeItem(at: tmp) }
            guard output.write(to: tmp, withOptions: [.userPasswordOption: pw, .ownerPasswordOption: pw]) else { return nil }
            return try? Data(contentsOf: tmp)
        }
        return output.dataRepresentation()
    }

    @discardableResult
    func save() -> Bool {
        commitInlineIfNeeded()
        guard let url else { return false }
        return write(to: url)
    }

    func write(to target: URL) -> Bool {
        guard let data = currentData() else {
            errorMessage = String(localized: "Belge hazırlanamadı.")
            return false
        }
        var coordError: NSError?
        var writeError: Error?
        let scoped = target.startAccessingSecurityScopedResource()
        defer { if scoped { target.stopAccessingSecurityScopedResource() } }
        NSFileCoordinator().coordinate(writingItemAt: target, options: .forReplacing, error: &coordError) { u in
            do { try data.write(to: u, options: .atomic) } catch {
                do { try data.write(to: u) } catch { writeError = error }
            }
        }
        if let e = coordError ?? (writeError as NSError?) {
            errorMessage = String(localized: "\"\(target.lastPathComponent)\" kaydedilemedi: \(e.localizedDescription)")
            return false
        }
        url = target
        isDirty = false
        modeStartDepth = undoDepth
        onSaved?(target)
        return true
    }

    /// Paylaşım / dışa aktarma için güncel belgenin geçici kopyası.
    func exportTempCopy(name: String? = nil) -> URL? {
        commitInlineIfNeeded()
        guard let data = currentData(), let dir = try? DocTools.freshOutputFolder() else { return nil }
        let file = dir.appendingPathComponent(name ?? displayName)
        do { try data.write(to: file) } catch { return nil }
        return file
    }
}

extension Notification.Name {
    static let qeniroOverlayNeedsRefresh = Notification.Name("qeniro.overlay.refresh")
    static let qeniroCommitInline = Notification.Name("qeniro.inline.commit")
}
