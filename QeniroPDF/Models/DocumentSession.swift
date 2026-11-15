import SwiftUI
import AppKit
import PDFKit

/// Metin işaretleme türleri (yüzen araç çubuğu).
enum MarkupKind: String {
    case highlight, underline, strikeOut
    var title: String {
        switch self {
        case .highlight: return "Vurgula"
        case .underline: return "Altını çiz"
        case .strikeOut: return "Üstünü çiz"
        }
    }
    var subtype: PDFAnnotationSubtype {
        switch self {
        case .highlight: return .highlight
        case .underline: return .underline
        case .strikeOut: return .strikeOut
        }
    }
    var color: NSColor {
        switch self {
        case .highlight: return NSColor(srgbRed: 1.0, green: 0.86, blue: 0.20, alpha: 0.6)
        case .underline: return NSColor(srgbRed: 0.18, green: 0.42, blue: 0.89, alpha: 1)
        case .strikeOut: return NSColor(srgbRed: 0.90, green: 0.20, blue: 0.18, alpha: 1)
        }
    }
}

enum ShapeKind: String {
    case rectangle, ellipse
}

/// Görüntüleyicide etkin olan araç.
enum ViewerTool: Equatable {
    case select, hand
    case addText, addImage, addLink
    case addSignature(UUID), addFillText, addCheckbox, addRadio, addDate, addTextField
    case redact
    /// Düzenle sekmesi: PDF içindeki gerçek metni değiştirme / yeni gerçek metin ekleme (PDFium).
    case editText
    case note, markup(MarkupKind), ink, shape(ShapeKind), crop
    case addDropdown, addSignatureField

    /// Sürükleyerek dikdörtgen çizilen araçlar.
    var isRectTool: Bool {
        switch self {
        case .addLink, .redact, .shape, .crop: return true
        default: return false
        }
    }
    var isPlacementTool: Bool {
        switch self {
        case .select, .hand, .addLink, .redact, .editText, .markup, .ink, .shape, .crop: return false
        default: return true
        }
    }

    var hint: String? {
        switch self {
        case .select, .hand: return nil
        case .addText, .addFillText: return "Metin eklemek için sayfada bir yere tıklayın."
        case .addImage: return "Görseli yerleştirmek için sayfada bir yere tıklayın."
        case .addLink: return "Bağlantı alanını sürükleyerek çizin; web adresi veya sayfa numarası sorulur."
        case .addSignature: return "İmzayı yerleştirmek için sayfada bir yere tıklayın."
        case .addCheckbox: return "Onay kutusu için sayfada bir yere tıklayın."
        case .addRadio: return "Radyo düğmesi için sayfada bir yere tıklayın."
        case .addDate: return "Tarihi yerleştirmek için sayfada bir yere tıklayın."
        case .addTextField: return "Form metin alanı için sayfada bir yere tıklayın."
        case .addDropdown: return "Açılır liste için sayfada bir yere tıklayın."
        case .addSignatureField: return "İmza alanı için sayfada bir yere tıklayın."
        case .redact: return "Kaldırılacak alanları sürükleyerek işaretleyin, sonra \"Sansürü Uygula\"ya basın."
        case .editText: return "Değiştirmek istediğiniz yazıya tıklayıp yazın; boş bir yere tıklayarak yeni metin ekleyin. Enter uygular, Esc vazgeçer."
        case .note: return "Yapışkan not eklemek için sayfada bir yere tıklayın."
        case .markup(let k): return "\(k.title): metni sürükleyerek seçin."
        case .ink: return "Sayfada sürükleyerek serbest çizin. Bitirince Esc'ye basın."
        case .shape: return "Şekli sürükleyerek çizin."
        case .crop: return "Sayfada kalmasını istediğiniz alanı sürükleyerek seçin."
        }
    }
}

/// Açık bir PDF sekmesinin tüm durumu: belge, görünüm, seçim, geri alma.
@MainActor
final class DocumentSession: ObservableObject, Identifiable {
    let id = UUID()
    @Published var url: URL?
    @Published private(set) var document: PDFDocument
    @Published var isDirty = false
    @Published var currentPageIndex = 0
    @Published var pageCount = 0
    @Published var scaleFactor: CGFloat = 1
    @Published var tool: ViewerTool = .select {
        didSet {
            pdfView.updateCursor()
            if oldValue != tool { pdfView.toolDidChange() }
        }
    }
    @Published var panel: SidePanel? = .tab
    @Published var viewerTab: ViewerTab = .allTools {
        didSet {
            guard viewerTab != oldValue else { return }
            if viewerTab == .edit {
                if tool == .select || tool == .hand { tool = .editText }
            } else if tool == .editText {
                tool = .select
            }
            if oldValue == .edit { selectedTextItem = nil; editNotice = nil }
        }
    }
    /// Düzenle sekmesinde seçili gerçek metin satırı (PDFium).
    @Published var selectedTextItem: PDFTextItem?
    /// Düzenleme sırasında gösterilen bilgi (ör. taranmış sayfa, yazı tipi değişimi).
    @Published var editNotice: String?
    @Published private(set) var signatureInfos: [PDFSignatureInfo] = []
    @Published private(set) var signaturesChecked = false
    @Published var showOrganizer = false
    @Published var showThumbnails = false
    @Published private(set) var selectedAnnotation: PDFAnnotation?
    @Published var textStyle = TextStyle()
    @Published var isSearching = false
    @Published var searchText = ""
    @Published private(set) var searchResults: [PDFSelection] = []
    @Published private(set) var searchIndex = 0
    @Published private(set) var revision = 0
    @Published var busyMessage: String?
    @Published var focusTextRequest = 0

    var pendingImage: NSImage?
    var password: String?
    /// Çizim ve şekil rengi.
    var inkColor = NSColor(srgbRed: 0.90, green: 0.20, blue: 0.18, alpha: 1)
    private var textEditor: PDFiumEditor?
    private var textItemCache: [Int: [PDFTextItem]] = [:]
    var onSaved: ((URL) -> Void)?

    let undoManager = UndoManager()
    let pdfView: QPDFView
    private(set) lazy var thumbnailView: PDFThumbnailView = {
        let t = PDFThumbnailView()
        t.pdfView = pdfView
        t.thumbnailSize = CGSize(width: 96, height: 128)
        t.backgroundColor = Theme.canvasNS
        return t
    }()

    private var tags: [ObjectIdentifier: QTag] = [:]
    private var underlines: [ObjectIdentifier: PDFAnnotation] = [:]
    private var observers: [NSObjectProtocol] = []

    var untitledName = "Adsız.pdf"
    var displayName: String { url?.lastPathComponent ?? untitledName }

    init(document: PDFDocument, url: URL?, password: String? = nil) {
        self.document = document
        self.url = url
        self.password = password
        self.pdfView = QPDFView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
        self.pageCount = document.pageCount
        pdfView.session = self
        configureView()
        Task { @MainActor [weak self] in self?.refreshSignatures() }
    }

    private func configureView() {
        undoManager.levelsOfUndo = 200
        pdfView.document = document
        pdfView.displayMode = .singlePageContinuous
        pdfView.displaysPageBreaks = true
        pdfView.autoScales = true
        pdfView.backgroundColor = Theme.canvasNS
        let nc = NotificationCenter.default
        observers.append(nc.addObserver(forName: .PDFViewPageChanged, object: pdfView, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.syncPage() }
        })
        observers.append(nc.addObserver(forName: .PDFViewScaleChanged, object: pdfView, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.scaleFactor = self.pdfView.scaleFactor
                self.pdfView.refreshOverlay()
            }
        })
        scaleFactor = pdfView.scaleFactor
    }

    // MARK: - Gezinme ve görünüm

    func syncPage() {
        if let p = pdfView.currentPage { currentPageIndex = document.index(for: p) }
        pageCount = document.pageCount
        pdfView.refreshOverlay()
    }

    func goTo(page index: Int) {
        guard let p = document.page(at: max(0, min(index, document.pageCount - 1))) else { return }
        pdfView.go(to: p)
        syncPage()
    }

    func nextPage() { goTo(page: currentPageIndex + 1) }
    func previousPage() { goTo(page: currentPageIndex - 1) }

    func zoomIn() { pdfView.autoScales = false; pdfView.scaleFactor = min(pdfView.scaleFactor * 1.25, 8) }
    func zoomOut() { pdfView.autoScales = false; pdfView.scaleFactor = max(pdfView.scaleFactor / 1.25, 0.1) }
    func setZoom(_ s: CGFloat) { pdfView.autoScales = false; pdfView.scaleFactor = s }
    func fitPage() {
        pdfView.autoScales = true
        scaleFactor = pdfView.scaleFactor
    }
    func fitWidth() {
        guard let page = pdfView.currentPage ?? document.page(at: 0) else { return }
        let w = page.bounds(for: .cropBox).width
        guard w > 0 else { return }
        pdfView.autoScales = false
        pdfView.scaleFactor = max(0.1, (pdfView.bounds.width - 40) / w)
    }

    func printDocument() {
        let info = NSPrintInfo.shared
        info.horizontalPagination = .fit
        info.verticalPagination = .fit
        pdfView.print(with: info, autoRotate: true)
    }

    // MARK: - Arama

    func search() {
        document.cancelFindString()
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { clearSearch(); return }
        let results = document.findString(q, withOptions: [.caseInsensitive, .diacriticInsensitive])
        for r in results { r.color = NSColor.systemYellow.withAlphaComponent(0.55) }
        searchResults = results
        pdfView.highlightedSelections = results
        searchIndex = 0
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
        pdfView.highlightedSelections = nil
        searchIndex = 0
    }

    // MARK: - Açıklama etiketleri

    func tag(of a: PDFAnnotation) -> QTag? {
        tags[ObjectIdentifier(a)] ?? a.persistedTag
    }

    private func setTag(_ a: PDFAnnotation, _ t: QTag) {
        tags[ObjectIdentifier(a)] = t
        if !(a is ImageAnnotation) {
            _ = a.setValue(t.rawValue, forAnnotationKey: QTag.key)
        }
    }

    /// Seçim aracıyla seçilip taşınabilen açıklamalar.
    func isSelectable(_ a: PDFAnnotation) -> Bool {
        if let t = tag(of: a) { return t != .underline }
        return !(a.isWidget || a.isLink || a.isPopup)
    }

    func isOwnWidget(_ a: PDFAnnotation) -> Bool { a.isWidget && tag(of: a) != nil }

    // MARK: - Seçim

    func select(_ a: PDFAnnotation?) {
        selectedAnnotation = a
        if a != nil { selectedTextItem = nil }
        if let a, a.isFreeText {
            var s = TextStyle.from(annotation: a)
            s.underline = underlines[ObjectIdentifier(a)] != nil
            textStyle = s
        }
        pdfView.refreshOverlay()
    }

    func requestTextFocus() {
        if panel == nil { panel = .tab }
        focusTextRequest += 1
    }

    // MARK: - Geri alınabilir açıklama işlemleri

    func changed(_ page: PDFPage?) {
        isDirty = true
        if let page { pdfView.annotationsChanged(on: page) }
        pdfView.refreshOverlay()
    }

    func add(_ a: PDFAnnotation, to page: PDFPage, tag t: QTag?, name: String = "Ekle") {
        if let t { setTag(a, t) }
        page.addAnnotation(a)
        if let line = underlines[ObjectIdentifier(a)], line.page == nil { page.addAnnotation(line) }
        changed(page)
        undoManager.registerUndo(withTarget: self) { s in
            MainActor.assumeIsolated { s.remove(a, name: name) }
        }
        undoManager.setActionName(name)
    }

    func remove(_ a: PDFAnnotation, name: String = "Sil") {
        guard let page = a.page else { return }
        if let line = underlines[ObjectIdentifier(a)] { line.page?.removeAnnotation(line) }
        page.removeAnnotation(a)
        if selectedAnnotation === a { selectedAnnotation = nil }
        changed(page)
        undoManager.registerUndo(withTarget: self) { s in
            MainActor.assumeIsolated { s.add(a, to: page, tag: nil, name: name) }
        }
        undoManager.setActionName(name)
    }

    func deleteSelected() {
        if let a = selectedAnnotation { remove(a) }
    }

    /// Sürükleme sırasında canlı güncelleme (geri alma kaydı yok).
    func liveBoundsChanged(_ a: PDFAnnotation) {
        syncUnderline(a)
        if let p = a.page { pdfView.annotationsChanged(on: p) }
        pdfView.refreshOverlay()
    }

    func setBounds(_ a: PDFAnnotation, to r: CGRect, from old: CGRect) {
        a.bounds = r
        syncUnderline(a)
        changed(a.page)
        undoManager.registerUndo(withTarget: self) { s in
            MainActor.assumeIsolated { s.setBounds(a, to: old, from: r) }
        }
        undoManager.setActionName("Taşı")
    }

    /// Sürükleme bittiğinde yeni konumu geri alınabilir olarak kaydeder.
    func commitBounds(_ a: PDFAnnotation, from old: CGRect) {
        let r = a.bounds
        guard r != old else { return }
        setBounds(a, to: r, from: old)
    }

    func toggleButton(_ a: PDFAnnotation) {
        guard a.isWidget else { return }
        if a.widgetControlType == .checkBoxControl {
            a.buttonWidgetState = a.buttonWidgetState == .onState ? .offState : .onState
        } else if a.widgetControlType == .radioButtonControl, let page = a.page {
            for other in page.annotations where other.isWidget && other.fieldName == a.fieldName {
                other.buttonWidgetState = other === a ? .onState : .offState
            }
        }
        changed(a.page)
    }

    // MARK: - Metin biçimi

    func updateStyle(_ change: (inout TextStyle) -> Void) {
        let before = textStyle
        var s = textStyle
        change(&s)
        textStyle = s
        if let item = selectedTextItem, selectedAnnotation == nil {
            // Gerçek metin: değişen özellikleri PDF içindeki nesneye uygula.
            var st = TextEditStyle()
            if s.family != before.family { st.family = s.family }
            if s.bold != before.bold { st.bold = s.bold }
            if s.italic != before.italic { st.italic = s.italic }
            if s.size != before.size { st.visualSize = s.size }
            if s.color != before.color { st.color = s.nsColor }
            st.alignment = s.alignment
            if s.underline && !before.underline { st.underline = true }
            let pending = pdfView.takeInlineText(for: item)
            commitTextEdit(item, newText: pending ?? item.text, style: st)
            return
        }
        guard let a = selectedAnnotation, a.isFreeText else { return }
        apply(style: s, to: a)
    }

    private func currentStyle(of a: PDFAnnotation) -> TextStyle {
        var s = TextStyle.from(annotation: a)
        s.underline = underlines[ObjectIdentifier(a)] != nil
        return s
    }

    func apply(style: TextStyle, to a: PDFAnnotation) {
        let old = currentStyle(of: a)
        a.font = style.makeFont()
        a.fontColor = style.nsColor
        a.alignment = style.alignment
        setUnderline(a, style.underline)
        fitFreeText(a)
        changed(a.page)
        undoManager.registerUndo(withTarget: self) { s in
            MainActor.assumeIsolated {
                s.apply(style: old, to: a)
                if s.selectedAnnotation === a { s.textStyle = old }
            }
        }
        undoManager.setActionName("Biçim")
    }

    func setContents(_ text: String, of a: PDFAnnotation) {
        a.contents = text
        fitFreeText(a)
        changed(a.page)
    }

    /// Metin kutusunu içeriğe göre büyütür (üst kenar sabit).
    func fitFreeText(_ a: PDFAnnotation) {
        guard a.isFreeText, let font = a.font else { syncUnderline(a); return }
        let text = (a.contents ?? "").isEmpty ? " " : (a.contents ?? " ")
        let attr = NSAttributedString(string: text, attributes: [.font: font])
        var r = a.bounds
        let single = attr.size()
        if let page = a.page {
            let pageMaxX = page.bounds(for: .mediaBox).maxX
            let wanted = ceil(single.width) + 10
            if !text.contains("\n"), wanted > r.width { r.size.width = min(wanted, max(r.width, pageMaxX - r.minX)) }
        }
        let fit = attr.boundingRect(with: NSSize(width: max(10, r.width - 6), height: 10000), options: [.usesLineFragmentOrigin, .usesFontLeading])
        let h = ceil(fit.height) + 6
        r = CGRect(x: r.minX, y: r.maxY - h, width: r.width, height: h)
        a.bounds = r
        syncUnderline(a)
    }

    private func setUnderline(_ a: PDFAnnotation, _ on: Bool) {
        let key = ObjectIdentifier(a)
        if on {
            if underlines[key] == nil, let page = a.page {
                let line = PDFAnnotation(bounds: CGRect(x: a.bounds.minX, y: a.bounds.minY, width: 10, height: 1), forType: .square, withProperties: nil)
                let b = PDFBorder(); b.lineWidth = 0
                line.border = b
                setTag(line, .underline)
                page.addAnnotation(line)
                underlines[key] = line
            }
            syncUnderline(a)
        } else if let line = underlines.removeValue(forKey: key) {
            line.page?.removeAnnotation(line)
        }
    }

    private func syncUnderline(_ a: PDFAnnotation) {
        guard let line = underlines[ObjectIdentifier(a)], let font = a.font else { return }
        let firstLine = (a.contents ?? "").components(separatedBy: "\n").first ?? ""
        let width = min(a.bounds.width - 6, NSAttributedString(string: firstLine, attributes: [.font: font]).size().width)
        let lineHeight = font.ascender - font.descender + font.leading
        let thickness = max(0.6, font.pointSize / 16)
        var x = a.bounds.minX + 3
        switch a.alignment {
        case .center: x = a.bounds.midX - width / 2
        case .right: x = a.bounds.maxX - 3 - width
        default: break
        }
        let y = a.bounds.maxY - 3 - font.ascender - max(1, -font.descender * 0.5)
        _ = lineHeight
        line.bounds = CGRect(x: x, y: y, width: max(1, width), height: thickness)
        line.color = a.fontColor ?? .black
        line.interiorColor = a.fontColor ?? .black
    }

    // MARK: - Nesne ekleme

    @discardableResult
    func makeFreeText(_ text: String, topLeft p: CGPoint, on page: PDFPage, tag t: QTag, name: String) -> PDFAnnotation {
        let style = textStyle
        let font = style.makeFont()
        let size = NSAttributedString(string: text, attributes: [.font: font]).size()
        let w = ceil(size.width) + 10, h = ceil(size.height) + 6
        let a = PDFAnnotation(bounds: CGRect(x: p.x, y: p.y - h, width: w, height: h), forType: .freeText, withProperties: nil)
        a.contents = text
        a.font = font
        a.fontColor = style.nsColor
        a.alignment = style.alignment
        a.color = .clear
        let b = PDFBorder(); b.lineWidth = 0
        a.border = b
        add(a, to: page, tag: t, name: name)
        if style.underline { setUnderline(a, true) }
        return a
    }

    /// Tıklama ile yerleştirilen araçlar.
    func place(at p: CGPoint, on page: PDFPage) {
        let current = tool
        tool = .select
        // Form hazırla panelinden eklenen alanlar "Uygula" ile düzleştirilmez, form alanı olarak kalır.
        let preparingForm = panel == .formPrepare
        switch current {
        case .addText:
            let a = makeFreeText("Metin", topLeft: p, on: page, tag: .text, name: "Metin ekle")
            select(a); requestTextFocus()
        case .addFillText:
            let a = makeFreeText("Metni yazın", topLeft: p, on: page, tag: .text, name: "Metin ekle")
            select(a); requestTextFocus()
        case .addDate:
            let a = makeFreeText("Tarih: " + Fmt.shortDate(), topLeft: p, on: page, tag: .date, name: "Tarih ekle")
            select(a)
        case .addImage:
            guard let img = pendingImage else { return }
            let r = fitRect(for: img.size, maxSide: 220, center: p)
            let a = ImageAnnotation(bounds: r, image: img, kind: .image)
            add(a, to: page, tag: .image, name: "Görsel ekle")
            select(a)
            pendingImage = nil
        case .addSignature(let id):
            guard let img = SignatureStore.shared.image(for: id) else { return }
            let r = fitRect(for: img.size, maxSide: 170, center: p)
            let a = ImageAnnotation(bounds: r, image: img, kind: .signature)
            add(a, to: page, tag: .signature, name: "İmza ekle")
            select(a)
        case .addCheckbox:
            let a = PDFAnnotation(bounds: CGRect(x: p.x - 8, y: p.y - 8, width: 16, height: 16), forType: .widget, withProperties: nil)
            a.widgetFieldType = .button
            a.widgetControlType = .checkBoxControl
            a.fieldName = "Onay_\(Int(Date().timeIntervalSince1970 * 1000) % 1_000_000)"
            a.buttonWidgetState = .onState
            a.backgroundColor = .white
            let b = PDFBorder(); b.lineWidth = 1
            a.border = b
            a.color = .black
            add(a, to: page, tag: preparingForm ? .formField : .checkbox, name: "Onay kutusu")
            select(a)
        case .addRadio:
            let a = PDFAnnotation(bounds: CGRect(x: p.x - 8, y: p.y - 8, width: 16, height: 16), forType: .widget, withProperties: nil)
            a.widgetFieldType = .button
            a.widgetControlType = .radioButtonControl
            a.fieldName = "Secenekler"
            a.buttonWidgetStateString = "Secim\(page.annotations.filter { $0.isWidget }.count + 1)"
            a.buttonWidgetState = .onState
            a.backgroundColor = .white
            let b = PDFBorder(); b.lineWidth = 1
            a.border = b
            a.color = .black
            add(a, to: page, tag: preparingForm ? .formField : .radio, name: "Radyo düğmesi")
            select(a)
        case .addTextField:
            let a = PDFAnnotation(bounds: CGRect(x: p.x, y: p.y - 22, width: 180, height: 22), forType: .widget, withProperties: nil)
            a.widgetFieldType = .text
            a.fieldName = "Alan_\(Int(Date().timeIntervalSince1970 * 1000) % 1_000_000)"
            a.widgetStringValue = ""
            a.font = NSFont(name: "Helvetica", size: 11) ?? NSFont.systemFont(ofSize: 11)
            a.backgroundColor = NSColor(srgbRed: 0.90, green: 0.93, blue: 0.99, alpha: 1)
            let b = PDFBorder(); b.lineWidth = 0.75
            a.border = b
            a.color = Theme.selectionNS
            add(a, to: page, tag: preparingForm ? .formField : .field, name: "Metin alanı")
            select(a)
        case .addDropdown:
            guard let raw = Dialogs.askText("Açılır liste", message: "Seçenekleri virgülle ayırarak yazın.",
                                            placeholder: "Seçenek 1, Seçenek 2", initial: "Seçenek 1, Seçenek 2, Seçenek 3") else { return }
            let options = raw.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            guard let firstOption = options.first else { return }
            let a = PDFAnnotation(bounds: CGRect(x: p.x, y: p.y - 22, width: 170, height: 22), forType: .widget, withProperties: nil)
            a.widgetFieldType = .choice
            a.isListChoice = false
            a.choices = options
            a.widgetStringValue = firstOption
            a.fieldName = "Liste_\(Int(Date().timeIntervalSince1970 * 1000) % 1_000_000)"
            a.font = NSFont(name: "Helvetica", size: 11) ?? NSFont.systemFont(ofSize: 11)
            a.backgroundColor = NSColor(srgbRed: 0.90, green: 0.93, blue: 0.99, alpha: 1)
            let b = PDFBorder(); b.lineWidth = 0.75
            a.border = b
            a.color = Theme.selectionNS
            add(a, to: page, tag: .formField, name: "Açılır liste")
            select(a)
        case .addSignatureField:
            let a = PDFAnnotation(bounds: CGRect(x: p.x, y: p.y - 40, width: 190, height: 40), forType: .widget, withProperties: nil)
            a.widgetFieldType = .signature
            a.fieldName = "Imza_\(Int(Date().timeIntervalSince1970 * 1000) % 1_000_000)"
            a.backgroundColor = NSColor(srgbRed: 1.0, green: 0.97, blue: 0.86, alpha: 1)
            let b = PDFBorder(); b.lineWidth = 1
            a.border = b
            a.color = NSColor.systemOrange
            add(a, to: page, tag: .sigField, name: "İmza alanı")
            select(a)
        case .note:
            guard let text = Dialogs.askText("Yorum ekle", message: "Yapışkan notun metnini yazın.", placeholder: "Yorum"),
                  !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
            let a = PDFAnnotation(bounds: CGRect(x: p.x - 10, y: p.y - 10, width: 20, height: 20), forType: .text, withProperties: nil)
            a.contents = text
            a.color = NSColor.systemYellow
            a.iconType = .comment
            a.userName = NSFullUserName().isEmpty ? NSUserName() : NSFullUserName()
            add(a, to: page, tag: .note, name: "Yorum ekle")
            select(a)
        default:
            break
        }
    }

    /// Yapışkan notun metnini değiştirir.
    func editNote(_ a: PDFAnnotation) {
        let old = a.contents ?? ""
        guard let text = Dialogs.askText("Yorumu düzenle", message: "", placeholder: "Yorum", initial: old), text != old else { return }
        setNoteText(a, text, old: old)
    }

    private func setNoteText(_ a: PDFAnnotation, _ text: String, old: String) {
        a.contents = text
        changed(a.page)
        undoManager.registerUndo(withTarget: self) { s in
            MainActor.assumeIsolated { s.setNoteText(a, old, old: text) }
        }
        undoManager.setActionName("Yorumu düzenle")
    }

    private func fitRect(for size: CGSize, maxSide: CGFloat, center p: CGPoint) -> CGRect {
        let w0 = max(size.width, 1), h0 = max(size.height, 1)
        let s = min(maxSide / w0, maxSide / h0, 1.5)
        let w = w0 * s, h = h0 * s
        return CGRect(x: p.x - w / 2, y: p.y - h / 2, width: w, height: h)
    }

    /// Sürükleyerek çizilen araçlar (bağlantı, sansür).
    func placeRect(_ r: CGRect, on page: PDFPage) {
        switch tool {
        case .addLink:
            tool = .select
            guard var link = Dialogs.askText("Bağlantı ekle", message: "Bağlantının açacağı web adresini veya sayfa numarasını yazın.", placeholder: "https://ornek.com veya 3") else { return }
            link = link.trimmingCharacters(in: .whitespaces)
            guard !link.isEmpty else { return }
            let a = PDFAnnotation(bounds: r, forType: .link, withProperties: nil)
            if let n = Int(link), let target = document.page(at: n - 1) {
                let top = target.bounds(for: .cropBox).maxY
                a.action = PDFActionGoTo(destination: PDFDestination(page: target, at: CGPoint(x: 0, y: top)))
            } else {
                if !link.contains("://") && !link.hasPrefix("mailto:") { link = "https://" + link }
                guard let u = URL(string: link) else { return }
                a.action = PDFActionURL(url: u)
            }
            let b = PDFBorder(); b.lineWidth = 0
            a.border = b
            add(a, to: page, tag: .link, name: "Bağlantı ekle")
            select(a)
        case .redact:
            addRedaction(r, on: page)
        case .shape(let kind):
            let a = PDFAnnotation(bounds: r, forType: kind == .rectangle ? .square : .circle, withProperties: nil)
            a.color = inkColor
            let b = PDFBorder(); b.lineWidth = 2
            a.border = b
            add(a, to: page, tag: .shape, name: "Şekil ekle")
        case .crop:
            tool = .select
            cropPages(to: r, from: page)
        default:
            break
        }
    }

    func addRedaction(_ r: CGRect, on page: PDFPage) {
        let a = PDFAnnotation(bounds: r, forType: .square, withProperties: nil)
        a.color = .black
        a.interiorColor = NSColor.black.withAlphaComponent(0.85)
        let b = PDFBorder(); b.lineWidth = 1
        a.border = b
        add(a, to: page, tag: .redact, name: "Sansür işareti")
    }

    /// Verilen metin seçimlerinin satırlarını sansür için işaretler.
    @discardableResult
    func markRedactions(for selections: [PDFSelection]) -> Int {
        var n = 0
        undoManager.beginUndoGrouping()
        for sel in selections {
            for line in sel.selectionsByLine() {
                for page in line.pages {
                    let r = line.bounds(for: page).insetBy(dx: -1, dy: -1)
                    guard r.width > 0.5, r.height > 0.5 else { continue }
                    addRedaction(r, on: page)
                    n += 1
                }
            }
        }
        undoManager.endUndoGrouping()
        undoManager.setActionName("Sansür işareti")
        return n
    }

    /// Seçili mevcut metnin üstünü beyaz kutuyla örtüp aynı metni düzenlenebilir kutuya koyar.
    func replaceSelectedText() {
        guard let sel = pdfView.currentSelection, let full = sel.string,
              !full.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            Dialogs.info("Önce metin seçin", "Seçim aracıyla değiştirmek istediğiniz metni sürükleyerek seçin, sonra bu düğmeye basın.")
            return
        }
        undoManager.beginUndoGrouping()
        let lines = sel.selectionsByLine()
        var last: PDFAnnotation?
        for page in sel.pages {
            let pageLines = lines.filter { $0.pages.contains(page) }
            let text = pageLines.compactMap { $0.string }.joined(separator: "\n")
            let r = sel.bounds(for: page).insetBy(dx: -1.5, dy: -1.5)
            guard r.width > 1, r.height > 1 else { continue }
            let cover = PDFAnnotation(bounds: r, forType: .square, withProperties: nil)
            cover.color = .white
            cover.interiorColor = .white
            let b = PDFBorder(); b.lineWidth = 0
            cover.border = b
            add(cover, to: page, tag: .cover, name: "Metni değiştir")
            let lineCount = CGFloat(max(1, pageLines.count))
            var style = textStyle
            style.size = max(6, min(72, ((r.height / lineCount) * 0.72).rounded()))
            if let attr = pageLines.first?.attributedString, attr.length > 0,
               let f = attr.attribute(.font, at: 0, effectiveRange: nil) as? NSFont {
                style.size = f.pointSize
                let traits = NSFontManager.shared.traits(of: f)
                style.bold = traits.contains(.boldFontMask)
                style.italic = traits.contains(.italicFontMask)
            }
            textStyle = style
            let a = makeFreeText(text.isEmpty ? full : text, topLeft: CGPoint(x: r.minX, y: r.maxY), on: page, tag: .text, name: "Metni değiştir")
            last = a
        }
        undoManager.endUndoGrouping()
        undoManager.setActionName("Metni değiştir")
        pdfView.clearSelection()
        if let last { select(last); requestTextFocus() }
    }

    // MARK: - Sayfa yapısı (geri alınabilir)

    private func structureChanged() {
        invalidateTextItems()
        isDirty = true
        pageCount = document.pageCount
        revision += 1
        pdfView.layoutDocumentView()
        syncPage()
    }

    func replacePage(at i: Int, with newPage: PDFPage, name: String) {
        guard let old = document.page(at: i) else { return }
        if let sel = selectedAnnotation, sel.page === old { selectedAnnotation = nil }
        document.removePage(at: i)
        document.insert(newPage, at: i)
        structureChanged()
        undoManager.registerUndo(withTarget: self) { s in
            MainActor.assumeIsolated { s.replacePage(at: i, with: old, name: name) }
        }
        undoManager.setActionName(name)
    }

    func movePage(from: Int, to: Int) {
        guard from != to, let p = document.page(at: from) else { return }
        document.removePage(at: from)
        let dest = max(0, min(to, document.pageCount))
        document.insert(p, at: dest)
        structureChanged()
        undoManager.registerUndo(withTarget: self) { s in
            MainActor.assumeIsolated { s.movePage(from: dest, to: from) }
        }
        undoManager.setActionName("Sayfa taşı")
    }

    func rotate(pages indices: [Int], by degrees: Int) {
        for i in indices {
            guard let p = document.page(at: i) else { continue }
            p.rotation = ((p.rotation + degrees) % 360 + 360) % 360
        }
        structureChanged()
        undoManager.registerUndo(withTarget: self) { s in
            MainActor.assumeIsolated { s.rotate(pages: indices, by: -degrees) }
        }
        undoManager.setActionName("Döndür")
    }

    func rotateCurrent(by degrees: Int) { rotate(pages: [currentPageIndex], by: degrees) }

    func deletePages(_ indices: [Int]) {
        let sorted = Array(Set(indices)).sorted()
        guard !sorted.isEmpty else { return }
        guard sorted.count < document.pageCount else {
            Dialogs.info("Tüm sayfalar silinemez", "Belgede en az bir sayfa kalmalıdır.")
            return
        }
        var removed: [(Int, PDFPage)] = []
        for i in sorted.reversed() {
            if let p = document.page(at: i) {
                removed.append((i, p))
                document.removePage(at: i)
            }
        }
        selectedAnnotation = nil
        structureChanged()
        undoManager.registerUndo(withTarget: self) { s in
            MainActor.assumeIsolated { s.restorePages(removed) }
        }
        undoManager.setActionName("Sayfa sil")
    }

    private func restorePages(_ items: [(Int, PDFPage)]) {
        for (i, p) in items.sorted(by: { $0.0 < $1.0 }) {
            document.insert(p, at: min(i, document.pageCount))
        }
        structureChanged()
        let indices = items.map { $0.0 }
        undoManager.registerUndo(withTarget: self) { s in
            MainActor.assumeIsolated { s.deletePages(indices) }
        }
        undoManager.setActionName("Sayfa sil")
    }

    func insertPages(_ pages: [PDFPage], at index: Int) {
        guard !pages.isEmpty else { return }
        let start = max(0, min(index, document.pageCount))
        for (k, p) in pages.enumerated() { document.insert(p, at: start + k) }
        structureChanged()
        let indices = Array(start..<(start + pages.count))
        undoManager.registerUndo(withTarget: self) { s in
            MainActor.assumeIsolated { s.deletePages(indices) }
        }
        undoManager.setActionName("Sayfa ekle")
    }

    func insertBlankPage(at index: Int) {
        let ref = document.page(at: max(0, min(index, document.pageCount - 1)))
        let size = ref?.bounds(for: .mediaBox).size ?? PageRenderer.a4
        if let blank = PageRenderer.blankPage(size: size) { insertPages([blank], at: index) }
    }

    func insertPDF(from url: URL, at index: Int) {
        do {
            let other = try DocTools.open(url)
            var pages: [PDFPage] = []
            for i in 0..<other.pageCount {
                if let p = other.page(at: i)?.copy() as? PDFPage { pages.append(p) }
            }
            insertPages(pages, at: index)
        } catch {
            Dialogs.error("Sayfalar eklenemedi", error)
        }
    }

    func extractPages(_ indices: [Int]) {
        let out = DocTools.rebuiltCopy(of: documentForWriting(), pages: indices.sorted())
        guard out.pageCount > 0 else { return }
        let base = url?.baseName ?? "Belge"
        guard let target = Dialogs.save(suggestedName: "\(base)_sayfalar.pdf", type: .pdf, title: "Sayfaları Çıkar") else { return }
        do { try DocTools.write(out, to: target) } catch { Dialogs.error("Kaydedilemedi", error) }
    }

    // MARK: - Uygula / Sansür / OCR

    /// İmza, metin, onay kutusu gibi eklenen öğeleri sayfaya kalıcı olarak gömer.
    func applyAnnotations() {
        var count = 0
        undoManager.beginUndoGrouping()
        for i in 0..<document.pageCount {
            guard let page = document.page(at: i) else { continue }
            let anns = page.annotations
            let flat = anns.filter { tag(of: $0)?.flattensOnApply ?? false }
            guard !flat.isEmpty else { continue }
            let keep = anns.filter { a in !flat.contains { $0 === a } }
            if let np = PageRenderer.rebuild(page: page, flatten: flat, keep: keep) {
                replacePage(at: i, with: np, name: "Uygula")
                count += 1
            }
        }
        undoManager.endUndoGrouping()
        undoManager.setActionName("Uygula")
        selectedAnnotation = nil
        if count == 0 {
            Dialogs.info("Uygulanacak öğe yok", "Önce imza, metin, onay kutusu veya tarih ekleyin.")
        }
    }

    var redactionMarkCount: Int {
        var n = 0
        for i in 0..<document.pageCount {
            n += document.page(at: i)?.annotations.filter { tag(of: $0) == .redact }.count ?? 0
        }
        return n
    }

    /// İşaretli alanları sayfadan gerçekten kaldırır: sayfa görüntüye çevrilir, alanlar siyahla
    /// boyanır ve (isteğe bağlı) kalan metin OCR ile görünmez katman olarak geri eklenir.
    func applyRedactions(restoreText: Bool) {
        var count = 0
        undoManager.beginUndoGrouping()
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
                replacePage(at: i, with: np, name: "Sansürle")
                count += 1
            }
        }
        undoManager.endUndoGrouping()
        undoManager.setActionName("Sansürle")
        if count == 0 {
            Dialogs.info("Sansür işareti yok", "Önce kaldırılacak alanları sürükleyerek işaretleyin.")
        } else {
            tool = .select
        }
    }

    /// Taranmış sayfalara aranabilir metin katmanı ekler.
    func runOCR(force: Bool) {
        guard let data = currentData() else { return }
        busyMessage = "Metin tanınıyor (OCR)…"
        Task {
            let result: [[OCRLine]?]
            do {
                result = try await Task.detached(priority: .userInitiated) {
                    try PDFOCRService.recognizeAll(data: data, skipPagesWithText: !force)
                }.value
            } catch {
                busyMessage = nil
                Dialogs.error("OCR başarısız", error)
                return
            }
            var count = 0
            undoManager.beginUndoGrouping()
            for (i, lines) in result.enumerated() {
                guard let lines, !lines.isEmpty, let page = document.page(at: i) else { continue }
                if let np = PageRenderer.rebuild(page: page, keep: page.annotations, extra: { ctx in
                    PageRenderer.drawInvisibleText(lines, in: ctx)
                }) {
                    replacePage(at: i, with: np, name: "OCR")
                    count += 1
                }
            }
            undoManager.endUndoGrouping()
            undoManager.setActionName("OCR")
            busyMessage = nil
            Dialogs.info(count > 0 ? "OCR tamamlandı" : "Tanınacak sayfa bulunamadı",
                         count > 0 ? "\(count) sayfaya aranabilir metin katmanı eklendi. Kaydetmeyi unutmayın." :
                                     "Tüm sayfalarda zaten seçilebilir metin var. Yine de çalıştırmak için \"OCR (tüm sayfalar)\" seçeneğini kullanın.")
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

    func invalidateTextItems() {
        textEditor = nil
        textItemCache = [:]
        pdfView.endInlineEdit(commit: false)
    }

    /// Sayfadaki düzenlenebilir metin satırları (önbellekli).
    func textItems(onPage index: Int) -> [PDFTextItem] {
        if let cached = textItemCache[index] { return cached }
        if textEditor == nil, let data = pdfiumSourceData() {
            textEditor = try? PDFiumEditor(data: data, password: password)
        }
        let items = (try? textEditor?.textItems(pageIndex: index)) ?? []
        textItemCache[index] = items
        return items
    }

    func textItem(at point: CGPoint, pageIndex: Int) -> PDFTextItem? {
        let hits = textItems(onPage: pageIndex).filter { $0.bounds.insetBy(dx: -2, dy: -2).contains(point) }
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
            s.color = Color(nsColor: item.color.withAlphaComponent(1))
            s.alignment = .left
            textStyle = s
        }
        pdfView.refreshOverlay()
    }

    /// Belgeyi PDFium ile düzenler, sonucu yeni PDFDocument olarak yükler (geri alınabilir).
    @discardableResult
    private func runPDFiumEdit(_ name: String, _ body: (PDFiumEditor) throws -> Void) -> Bool {
        do {
            guard let data = pdfiumSourceData() else { throw QPDFError.message("Belge hazırlanamadı.") }
            let editor = try PDFiumEditor(data: data, password: password)
            try body(editor)
            let out = try editor.save()
            guard let newDoc = PDFDocument(data: out) else { throw QPDFError.message("Düzenlenen belge açılamadı.") }
            if newDoc.isLocked, let pw = password { _ = newDoc.unlock(withPassword: pw) }
            guard newDoc.pageCount == document.pageCount else {
                throw QPDFError.message("Sayfa sayısı beklenmedik şekilde değişti; işlem iptal edildi.")
            }
            replaceDocument(with: newDoc, name: name)
            return true
        } catch {
            Dialogs.error("\(name) yapılamadı", error)
            return false
        }
    }

    /// Belgenin tamamını başka bir PDFDocument ile değiştirir; görünüm konumu ve yakınlaştırma korunur.
    func replaceDocument(with newDoc: PDFDocument, name: String) {
        let old = document
        pdfView.endInlineEdit(commit: false)
        // Özel çizimli görsel/imza açıklamalarını yeni sayfalara taşı.
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
        selectedTextItem = nil
        clearSearch()
        document = newDoc
        pdfView.document = newDoc
        pdfView.autoScales = auto
        if !auto { pdfView.scaleFactor = scale }
        if destIndex != NSNotFound, let p = newDoc.page(at: destIndex) {
            if let destPoint {
                pdfView.go(to: PDFDestination(page: p, at: destPoint))
            } else {
                pdfView.go(to: p)
            }
        }
        textEditor = nil
        textItemCache = [:]
        isDirty = true
        pageCount = newDoc.pageCount
        revision += 1
        syncPage()
        undoManager.registerUndo(withTarget: self) { s in
            MainActor.assumeIsolated { s.replaceDocument(with: old, name: name) }
        }
        undoManager.setActionName(name)
    }

    /// Satır içi düzenlemeyi PDF'e yazar: aynı nesnede değiştirir ya da benzer yazı tipiyle yeniden yazar.
    func commitTextEdit(_ item: PDFTextItem, newText: String, style: TextEditStyle? = nil) {
        guard style != nil || newText != item.text else { return }
        let deleting = newText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        var result: TextEditResult?
        let ok = runPDFiumEdit(deleting ? "Metni sil" : "Metni düzenle") { editor in
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
            editNotice = "Özgün yazı tipi yeni karakterleri içermediği için bu satır benzer bir sistem yazı tipiyle yeniden yazıldı (metin PDF içinde gerçekten değişti)."
        }
        pdfView.refreshOverlay()
    }

    private static func overlapArea(_ a: CGRect, _ b: CGRect) -> CGFloat {
        let r = a.intersection(b)
        return r.isNull ? 0 : r.width * r.height
    }

    /// Boş bir yere tıklanınca yazılan metni gerçek metin nesnesi olarak ekler.
    func insertNewText(_ text: String, topLeft: CGPoint, on page: PDFPage) {
        let idx = document.index(for: page)
        guard idx != NSNotFound else { return }
        let style = textStyle
        let size = style.size
        let rotation = page.rotation
        // Sol üst köşeden yazı yüksekliği kadar "aşağı" (döndürülmüş sayfada metin yönünde) taban çizgisi.
        let angle = CGFloat(rotation) * .pi / 180
        let ascent = size * 0.8
        let baseline = CGPoint(x: topLeft.x + sin(angle) * ascent, y: topLeft.y - cos(angle) * ascent)
        var box = CGRect.zero
        let ok = runPDFiumEdit("Metin ekle") { editor in
            box = try editor.insertText(text, pageIndex: idx, baseline: baseline, family: style.family,
                                        bold: style.bold, italic: style.italic, size: size,
                                        color: style.nsColor, rotation: rotation, underline: style.underline)
        }
        if ok {
            selectedTextItem = textItems(onPage: idx).first { $0.bounds.intersects(box) }
            pdfView.refreshOverlay()
        }
    }

    func deleteSelectedTextItem() {
        guard let item = selectedTextItem else { return }
        commitTextEdit(item, newText: "")
    }

    // MARK: - Üstbilgi / altbilgi / filigran (gerçek metin)

    func applyHeaderFooter(header: String, footer: String, numberFormat: String?,
                           position: PDFiumEditor.NumberPosition, size: CGFloat, color: NSColor, margin: CGFloat) {
        let date = Fmt.shortDate()
        runPDFiumEdit("Üstbilgi ve altbilgi") { editor in
            try editor.addHeaderFooter(header: header, footer: footer, numberFormat: numberFormat,
                                       numberPosition: position, size: size, color: color, margin: margin, date: date)
        }
    }

    func applyWatermark(text: String, size: CGFloat, color: NSColor, opacity: CGFloat, angle: CGFloat, bold: Bool) {
        runPDFiumEdit("Filigran") { editor in
            try editor.addWatermark(text, size: size, color: color, opacity: opacity, angle: angle, bold: bold)
        }
    }

    // MARK: - İşaretleme, çizim, kırpma

    /// Seçili metne vurgu / altı çizili / üstü çizili açıklaması ekler.
    func applyMarkup(_ kind: MarkupKind) {
        guard let sel = pdfView.currentSelection, let str = sel.string,
              !str.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        var count = 0
        undoManager.beginUndoGrouping()
        for line in sel.selectionsByLine() {
            for page in line.pages {
                let r = line.bounds(for: page)
                guard r.width > 0.5, r.height > 0.5 else { continue }
                let a = PDFAnnotation(bounds: r, forType: kind.subtype, withProperties: nil)
                a.color = kind.color
                a.quadrilateralPoints = [
                    NSValue(point: NSPoint(x: 0, y: r.height)), NSValue(point: NSPoint(x: r.width, y: r.height)),
                    NSValue(point: NSPoint(x: 0, y: 0)), NSValue(point: NSPoint(x: r.width, y: 0))
                ]
                add(a, to: page, tag: .markup, name: kind.title)
                count += 1
            }
        }
        undoManager.endUndoGrouping()
        if count > 0 { undoManager.setActionName(kind.title) }
        pdfView.clearSelection()
    }

    /// Serbest çizim (ink) açıklaması ekler. Noktalar sayfa koordinatlarındadır.
    func addInk(_ points: [CGPoint], on page: PDFPage) {
        guard points.count > 1 else { return }
        let lineWidth: CGFloat = 2
        var minX = CGFloat.greatestFiniteMagnitude, minY = CGFloat.greatestFiniteMagnitude
        var maxX = -CGFloat.greatestFiniteMagnitude, maxY = -CGFloat.greatestFiniteMagnitude
        for p in points {
            minX = min(minX, p.x); minY = min(minY, p.y)
            maxX = max(maxX, p.x); maxY = max(maxY, p.y)
        }
        let b = CGRect(x: minX, y: minY, width: max(maxX - minX, 1), height: max(maxY - minY, 1))
            .insetBy(dx: -lineWidth * 2, dy: -lineWidth * 2)
        // Yollar açıklama uzayındadır (sınır kutusunun köşesine göre).
        let path = NSBezierPath()
        path.move(to: NSPoint(x: points[0].x - b.minX, y: points[0].y - b.minY))
        for p in points.dropFirst() { path.line(to: NSPoint(x: p.x - b.minX, y: p.y - b.minY)) }
        path.lineWidth = lineWidth
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        let a = PDFAnnotation(bounds: b, forType: .ink, withProperties: nil)
        a.add(path)
        let border = PDFBorder()
        border.lineWidth = lineWidth
        a.border = border
        a.color = inkColor
        add(a, to: page, tag: .ink, name: "Çiz")
    }

    /// Sürüklenen alana göre kırpma kutusu ayarlar (yalnızca bu sayfa veya tüm sayfalar).
    func cropPages(to r: CGRect, from page: PDFPage) {
        let idx = document.index(for: page)
        guard idx != NSNotFound else { return }
        let alert = NSAlert()
        alert.messageText = "Sayfayı kırp"
        alert.informativeText = "Seçilen alanın dışı gizlenir (kırpma kutusu). Hangi sayfalara uygulansın?"
        alert.addButton(withTitle: "Yalnızca bu sayfa")
        alert.addButton(withTitle: "Tüm sayfalar")
        alert.addButton(withTitle: "Vazgeç")
        let indices: [Int]
        switch alert.runModal() {
        case .alertFirstButtonReturn: indices = [idx]
        case .alertSecondButtonReturn: indices = Array(0..<document.pageCount)
        default: return
        }
        setCropBoxes(indices.map { ($0, r) })
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
        undoManager.registerUndo(withTarget: self) { s in
            MainActor.assumeIsolated { s.setCropBoxes(old) }
        }
        undoManager.setActionName("Kırp")
    }

    // MARK: - Paylaşma ve imzalar

    /// "Yorum için gönder": yorumlu PDF'i geçici dosyaya yazıp macOS paylaşım menüsünü açar.
    func shareForReview() {
        guard let data = currentData() else {
            Dialogs.info("Belge hazırlanamadı")
            return
        }
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("qeniro-share-\(UUID().uuidString)", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let file = dir.appendingPathComponent(displayName)
            try data.write(to: file)
            let picker = NSSharingServicePicker(items: [file])
            let v = pdfView
            let anchor = NSRect(x: 60, y: v.isFlipped ? 20 : v.bounds.maxY - 20, width: 1, height: 1)
            picker.show(relativeTo: anchor, of: v, preferredEdge: .minY)
        } catch {
            Dialogs.error("Paylaşılamadı", error)
        }
    }

    var signatureProblem: Bool {
        signatureInfos.contains { $0.status != .valid }
    }

    /// Diskteki dosyanın dijital imzalarını doğrular (bant ve İmzaları doğrula paneli için).
    func refreshSignatures() {
        guard let url, let data = try? Data(contentsOf: url) else {
            signatureInfos = []
            signaturesChecked = true
            return
        }
        signatureInfos = SignatureVerifier.verify(fileData: data, password: password)
        signaturesChecked = true
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

    func currentData() -> Data? {
        documentForWriting().dataRepresentation()
    }

    @discardableResult
    func save() -> Bool {
        if let url { return write(to: url) }
        return saveAs()
    }

    @discardableResult
    func saveAs() -> Bool {
        guard let target = Dialogs.save(suggestedName: displayName, type: .pdf, title: "Farklı Kaydet",
                                        directory: url?.deletingLastPathComponent()) else { return false }
        return write(to: target)
    }

    func write(to target: URL) -> Bool {
        let output = documentForWriting()
        var options: [PDFDocumentWriteOption: Any]?
        if let pw = password, !pw.isEmpty {
            options = [.userPasswordOption: pw, .ownerPasswordOption: pw]
        }
        let tmp = target.deletingLastPathComponent().appendingPathComponent(".qeniro-\(UUID().uuidString).pdf")
        do {
            try DocTools.write(output, to: tmp, options: options)
            if FileManager.default.fileExists(atPath: target.path) {
                _ = try FileManager.default.replaceItemAt(target, withItemAt: tmp)
            } else {
                try FileManager.default.moveItem(at: tmp, to: target)
            }
        } catch {
            try? FileManager.default.removeItem(at: tmp)
            Dialogs.error("Kaydedilemedi", error)
            return false
        }
        url = target
        isDirty = false
        onSaved?(target)
        refreshSignatures()
        return true
    }
}
