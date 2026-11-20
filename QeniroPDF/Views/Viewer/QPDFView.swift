import AppKit
import PDFKit

/// Seçili açıklamanın mavi kutusunu, tutamaçlarını, düzenlenebilir metin çerçevelerini,
/// çizim önizlemesini ve sürükleme dikdörtgenini çizen şeffaf katman.
final class SelectionOverlayView: NSView {
    weak var pdfView: QPDFView?

    override var isFlipped: Bool { pdfView?.isFlipped ?? false }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draw(_ dirtyRect: NSRect) {
        guard let v = pdfView, let s = v.session else { return }
        let blue = Theme.selectionNS
        if let a = s.selectedAnnotation, let page = a.page, v.document?.index(for: page) != NSNotFound {
            let r = v.convert(a.bounds, from: page).insetBy(dx: -2, dy: -2)
            blue.withAlphaComponent(0.08).setFill()
            NSBezierPath(rect: r).fill()
            let path = NSBezierPath(rect: r)
            path.lineWidth = 1.5
            blue.setStroke()
            path.stroke()
            if !a.isWidget || a.widgetFieldType == .text {
                for p in v.handlePoints(for: a, on: page) {
                    let h = NSRect(x: p.x - 4, y: p.y - 4, width: 8, height: 8)
                    let hp = NSBezierPath(ovalIn: h)
                    NSColor.white.setFill()
                    hp.fill()
                    hp.lineWidth = 1.5
                    blue.setStroke()
                    hp.stroke()
                }
            }
        }
        // Düzenle sekmesi: düzenlenebilir satırlar kesikli lacivert (%45), üzerine gelinen satır daha belirgin,
        // seçili satır 1.5 pt lacivert çerçeve + 6 pt köşe + %6 dolgu.
        if s.tool == .editText, !v.isInlineEditing {
            for page in v.visiblePages {
                let idx = s.document.index(for: page)
                guard idx != NSNotFound else { continue }
                for item in s.textItems(onPage: idx) where item != s.selectedTextItem && item != v.hoverTextItem {
                    let r = v.convert(item.bounds, from: page).insetBy(dx: -3, dy: -3)
                    let p = NSBezierPath(roundedRect: r, xRadius: 3, yRadius: 3)
                    p.lineWidth = 1
                    p.setLineDash([4, 3], count: 2, phase: 0)
                    blue.withAlphaComponent(0.45).setStroke()
                    p.stroke()
                }
            }
        }
        if let item = v.hoverTextItem, item != s.selectedTextItem, !v.isInlineEditing,
           let page = s.document.page(at: item.pageIndex) {
            let r = v.convert(item.bounds, from: page).insetBy(dx: -3, dy: -3)
            let p = NSBezierPath(roundedRect: r, xRadius: 3, yRadius: 3)
            p.lineWidth = 1
            p.setLineDash([4, 3], count: 2, phase: 0)
            blue.withAlphaComponent(0.9).setStroke()
            p.stroke()
        }
        if let item = s.selectedTextItem, !v.isInlineEditing, let page = s.document.page(at: item.pageIndex) {
            let r = v.convert(item.bounds, from: page).insetBy(dx: -4, dy: -4)
            let p = NSBezierPath(roundedRect: r, xRadius: 6, yRadius: 6)
            blue.withAlphaComponent(0.06).setFill()
            p.fill()
            p.lineWidth = 1.5
            blue.setStroke()
            p.stroke()
        }
        if let pts = v.inkPreview, pts.count > 1 {
            let p = NSBezierPath()
            p.move(to: pts[0])
            for pt in pts.dropFirst() { p.line(to: pt) }
            p.lineWidth = max(1, 2 * v.scaleFactor)
            p.lineCapStyle = .round
            p.lineJoinStyle = .round
            s.inkColor.setStroke()
            p.stroke()
        }
        if let d = v.dragRect {
            let isRedact = s.tool == .redact
            (isRedact ? NSColor.black.withAlphaComponent(0.35) : blue.withAlphaComponent(0.12)).setFill()
            NSBezierPath(rect: d).fill()
            let p = NSBezierPath(rect: d)
            p.lineWidth = 1
            p.setLineDash([4, 3], count: 2, phase: 0)
            (isRedact ? NSColor.systemRed : blue).setStroke()
            p.stroke()
        }
    }
}

/// Satır içi metin kutusunun klavye olaylarını (Enter, Esc, odak kaybı) yakalar.
final class InlineFieldController: NSObject, NSTextFieldDelegate {
    var onFinish: ((Bool) -> Void)?
    var onChange: (() -> Void)?

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(NSResponder.insertNewline(_:)) {
            onFinish?(true)
            return true
        }
        if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
            onFinish?(false)
            return true
        }
        return false
    }

    func controlTextDidChange(_ obj: Notification) {
        onChange?()
    }

    func controlTextDidEndEditing(_ obj: Notification) {
        onFinish?(true)
    }
}

/// Açıklama seçme/taşıma/boyutlandırma, el aracı, yerleştirme araçları, işaretleme, çizim
/// ve gerçek metin düzenleme (satır içi kutu) ekleyen PDFView.
final class QPDFView: PDFView {
    weak var session: DocumentSession?
    let overlay = SelectionOverlayView()
    var dragRect: NSRect?

    /// Düzenle sekmesinde fare altındaki metin satırı.
    private(set) var hoverTextItem: PDFTextItem?
    /// Serbest çizim önizlemesi (görünüm koordinatları).
    private(set) var inkPreview: [NSPoint]?

    enum Corner { case bottomLeft, bottomRight, topLeft, topRight }

    private enum DragMode {
        case none
        case move(PDFAnnotation, PDFPage, CGRect, CGPoint)
        case resize(PDFAnnotation, PDFPage, CGRect, Corner, CGPoint)
        case rect(PDFPage, NSPoint)
        case pan(NSPoint, NSPoint)
        case ink(PDFPage)
    }

    private var drag: DragMode = .none
    private var didDrag = false
    private var scrollObserverAttached = false
    private var trackingAreaRef: NSTrackingArea?
    private var inkPagePoints: [CGPoint] = []
    private var markupPending = false

    // Satır içi düzenleme
    private var inlineField: NSTextField?
    /// Düzenleme kutusunun üstündeki koyu kapsül etiket ("Düzenleniyor · Yazı tipi boyut").
    private var inlineBadge: NSView?
    private let inlineController = InlineFieldController()
    private var inlineItem: PDFTextItem?
    private var inlinePage: PDFPage?
    private var inlineAnchor: CGRect = .zero
    private var inlineEnding = false
    var isInlineEditing: Bool { inlineField != nil }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupOverlay()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupOverlay()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    private func setupOverlay() {
        overlay.pdfView = self
        overlay.frame = bounds
        overlay.autoresizingMask = [.width, .height]
        overlay.wantsLayer = true
        addSubview(overlay)
    }

    override var undoManager: UndoManager? { session?.undoManager ?? super.undoManager }
    override var acceptsFirstResponder: Bool { true }

    override func layout() {
        super.layout()
        overlay.frame = bounds
        if let field = inlineField {
            if subviews.last !== field { addSubview(field, positioned: .above, relativeTo: nil) }
        } else if subviews.last !== overlay {
            addSubview(overlay, positioned: .above, relativeTo: nil)
        }
        attachScrollObserver()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let t = trackingAreaRef { removeTrackingArea(t) }
        let t = NSTrackingArea(rect: .zero, options: [.mouseMoved, .activeInKeyWindow, .inVisibleRect], owner: self, userInfo: nil)
        addTrackingArea(t)
        trackingAreaRef = t
    }

    func attachScrollObserver() {
        guard !scrollObserverAttached, let sv = documentView?.enclosingScrollView else { return }
        scrollObserverAttached = true
        sv.contentView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(self, selector: #selector(viewportChanged(_:)),
                                               name: NSView.boundsDidChangeNotification, object: sv.contentView)
    }

    @objc private func viewportChanged(_ note: Notification) {
        positionInlineField()
        refreshOverlay()
    }

    func refreshOverlay() {
        positionInlineField()
        overlay.needsDisplay = true
    }

    func updateCursor() {
        guard let s = session else { return }
        switch s.tool {
        case .hand: NSCursor.openHand.set()
        case .select: NSCursor.arrow.set()
        case .editText, .markup: NSCursor.iBeam.set()
        default: NSCursor.crosshair.set()
        }
    }

    /// Araç değişince yarım kalan işlemleri kapatır.
    func toolDidChange() {
        endInlineEdit(commit: true)
        hoverTextItem = nil
        inkPreview = nil
        inkPagePoints = []
        markupPending = false
        dragRect = nil
        refreshOverlay()
    }

    override func mouseMoved(with event: NSEvent) {
        super.mouseMoved(with: event)
        guard let s = session else { return }
        if s.tool == .editText {
            updateTextHover(event)
        } else if s.tool != .select {
            updateCursor()
        }
    }

    private func updateTextHover(_ event: NSEvent) {
        guard let s = session else { return }
        let vp = convert(event.locationInWindow, from: nil)
        var found: PDFTextItem?
        var overPage = false
        if !isInlineEditing, let page = page(for: vp, nearest: false) {
            overPage = true
            let idx = s.document.index(for: page)
            if idx != NSNotFound { found = s.textItem(at: convert(vp, to: page), pageIndex: idx) }
        }
        if found != hoverTextItem {
            hoverTextItem = found
            refreshOverlay()
        }
        (overPage ? NSCursor.iBeam : NSCursor.arrow).set()
    }

    // MARK: - Yardımcılar

    func handlePoints(for a: PDFAnnotation, on page: PDFPage) -> [NSPoint] {
        let b = a.bounds.insetBy(dx: -2, dy: -2)
        return [CGPoint(x: b.minX, y: b.minY), CGPoint(x: b.maxX, y: b.minY),
                CGPoint(x: b.minX, y: b.maxY), CGPoint(x: b.maxX, y: b.maxY)]
            .map { convert($0, from: page) }
    }

    private func handleHit(_ viewPoint: NSPoint, _ a: PDFAnnotation, _ page: PDFPage) -> Corner? {
        if a.isWidget && a.widgetFieldType != .text { return nil }
        let corners: [Corner] = [.bottomLeft, .bottomRight, .topLeft, .topRight]
        for (i, p) in handlePoints(for: a, on: page).enumerated() {
            if abs(p.x - viewPoint.x) <= 6 && abs(p.y - viewPoint.y) <= 6 { return corners[i] }
        }
        return nil
    }

    private func topSelectableAnnotation(at pp: CGPoint, on page: PDFPage) -> PDFAnnotation? {
        guard let s = session else { return nil }
        for a in page.annotations.reversed() where s.isSelectable(a) {
            if a.bounds.insetBy(dx: -3, dy: -3).contains(pp) { return a }
        }
        return nil
    }

    // MARK: - Satır içi metin düzenleme

    static func displayFont(for item: PDFTextItem, scale: CGFloat) -> NSFont {
        let size = max(6, item.visualSize * scale)
        if !item.baseFontName.isEmpty, let f = NSFont(name: item.baseFontName, size: size) { return f }
        var traits: NSFontTraitMask = []
        if item.bold { traits.insert(.boldFontMask) }
        if item.italic { traits.insert(.italicFontMask) }
        if let f = NSFontManager.shared.font(withFamily: item.familyName, traits: traits, weight: 5, size: size) { return f }
        return NSFont.systemFont(ofSize: size)
    }

    /// Bir metin satırının (veya yeni metin için tıklanan noktanın) üstünde düzenleme kutusu açar.
    func beginInlineEdit(item: PDFTextItem?, page: PDFPage, at pagePoint: CGPoint) {
        endInlineEdit(commit: true)
        guard let s = session else { return }
        let font: NSFont
        let text: String
        let color: NSColor
        if let item {
            font = Self.displayFont(for: item, scale: scaleFactor)
            text = item.text
            color = item.color.withAlphaComponent(1)
            inlineAnchor = item.bounds
        } else {
            let size = s.textStyle.size
            let base = s.textStyle.makeFont()
            font = NSFont(descriptor: base.fontDescriptor, size: max(6, size * scaleFactor)) ?? NSFont.systemFont(ofSize: max(6, size * scaleFactor))
            text = ""
            color = s.textStyle.nsColor
            inlineAnchor = CGRect(x: pagePoint.x, y: pagePoint.y - size * 1.25, width: max(80, size * 6), height: size * 1.25)
        }
        let field = NSTextField(string: text)
        field.font = font
        field.textColor = color
        field.isBordered = false
        field.isBezeled = false
        field.drawsBackground = true
        field.backgroundColor = Theme.hex(0xF4F6F7)
        field.focusRingType = .none
        field.usesSingleLineMode = true
        field.lineBreakMode = .byClipping
        field.cell?.isScrollable = true
        field.cell?.wraps = false
        field.placeholderString = item == nil ? "Metin yazın" : nil
        field.wantsLayer = true
        field.layer?.borderColor = Theme.navyNS.cgColor
        field.layer?.borderWidth = 1.5
        field.layer?.cornerRadius = 6
        field.layer?.masksToBounds = true
        field.delegate = inlineController
        inlineController.onFinish = { [weak self] commit in self?.endInlineEdit(commit: commit) }
        inlineController.onChange = { [weak self] in self?.positionInlineField() }
        inlineField = field
        inlineItem = item
        inlinePage = page
        addSubview(field, positioned: .above, relativeTo: nil)
        let family = item?.familyName ?? s.textStyle.family
        let pt = item?.visualSize ?? s.textStyle.size
        let ptText = pt == pt.rounded() ? "\(Int(pt))" : String(format: "%.1f", Double(pt))
        let label = NSTextField(labelWithString: "Düzenleniyor · \(family) \(ptText)")
        label.font = NSFont.systemFont(ofSize: 11, weight: .medium)
        label.textColor = .white
        label.sizeToFit()
        let badge = NSView(frame: NSRect(x: 0, y: 0, width: label.frame.width + 18, height: 22))
        badge.wantsLayer = true
        badge.layer?.backgroundColor = Theme.hex(0x121A21).cgColor
        badge.layer?.cornerRadius = 11
        label.frame.origin = NSPoint(x: 9, y: (22 - label.frame.height) / 2)
        badge.addSubview(label)
        badge.setAccessibilityElement(true)
        badge.setAccessibilityLabel("Düzenleniyor: \(family) \(ptText) punto")
        addSubview(badge, positioned: .above, relativeTo: nil)
        inlineBadge = badge
        positionInlineField()
        window?.makeFirstResponder(field)
        if let editor = field.currentEditor() {
            editor.selectedRange = NSRange(location: (text as NSString).length, length: 0)
        }
        hoverTextItem = nil
        overlay.needsDisplay = true
    }

    private func positionInlineField() {
        guard let field = inlineField, let page = inlinePage, document?.index(for: page) != NSNotFound else { return }
        let r = convert(inlineAnchor, from: page)
        let font = field.font ?? NSFont.systemFont(ofSize: 13)
        let lineHeight = font.ascender - font.descender + font.leading + 6
        let textWidth = NSAttributedString(string: field.stringValue.isEmpty ? (field.placeholderString ?? " ") : field.stringValue,
                                           attributes: [.font: font]).size().width + 24
        let w = max(r.width + 12, textWidth, 60)
        let h = max(r.height + 4, lineHeight)
        field.frame = NSRect(x: r.minX - 4, y: r.midY - h / 2, width: w, height: h)
        if let badge = inlineBadge {
            let bh = badge.frame.height
            let y = isFlipped ? field.frame.minY - bh - 4 : field.frame.maxY + 4
            badge.setFrameOrigin(NSPoint(x: field.frame.minX, y: y))
        }
    }

    /// Düzenleme kutusunu kapatır; `commit` ise metni PDF'e yazar (ana döngünün sonraki turunda).
    func endInlineEdit(commit: Bool) {
        guard let field = inlineField, !inlineEnding else { return }
        inlineEnding = true
        let text = field.stringValue
        let item = inlineItem
        let page = inlinePage
        let anchor = inlineAnchor
        inlineField = nil
        inlineItem = nil
        inlinePage = nil
        inlineController.onFinish = nil
        inlineController.onChange = nil
        field.delegate = nil
        field.removeFromSuperview()
        inlineBadge?.removeFromSuperview()
        inlineBadge = nil
        if let w = window, w.firstResponder == nil || w.firstResponder === w { w.makeFirstResponder(self) }
        inlineEnding = false
        overlay.needsDisplay = true
        guard commit, let s = session, let page else { return }
        Task { @MainActor [weak s] in
            guard let s else { return }
            if let item {
                if text != item.text { s.commitTextEdit(item, newText: text) }
            } else if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                s.insertNewText(text, topLeft: CGPoint(x: anchor.minX, y: anchor.maxY), on: page)
            }
        }
    }

    /// Panelden biçim değişikliği gelince, açık kutudaki yazılmış metni alır ve kutuyu kapatır.
    func takeInlineText(for item: PDFTextItem) -> String? {
        guard let field = inlineField, inlineItem == item else { return nil }
        let t = field.stringValue
        endInlineEdit(commit: false)
        return t
    }

    // MARK: - Fare

    override func mouseDown(with event: NSEvent) {
        guard let s = session else { super.mouseDown(with: event); return }
        if isInlineEditing {
            // Açık düzenleme kutusunun dışına tıklamak düzenlemeyi uygular.
            endInlineEdit(commit: true)
            return
        }
        window?.makeFirstResponder(self)
        let vp = convert(event.locationInWindow, from: nil)
        didDrag = false
        drag = .none

        switch s.tool {
        case .hand:
            if let sv = documentView?.enclosingScrollView {
                drag = .pan(event.locationInWindow, sv.contentView.bounds.origin)
                NSCursor.closedHand.set()
            }
        case .addLink, .redact, .shape, .crop:
            guard let page = page(for: vp, nearest: true) else { return }
            drag = .rect(page, vp)
            dragRect = NSRect(origin: vp, size: .zero)
        case .select:
            if let a = s.selectedAnnotation, let page = a.page, let corner = handleHit(vp, a, page) {
                drag = .resize(a, page, a.bounds, corner, convert(vp, to: page))
                return
            }
            if let page = page(for: vp, nearest: false) {
                let pp = convert(vp, to: page)
                if let a = topSelectableAnnotation(at: pp, on: page) {
                    // Kendi metin alanımıza çift tıklayınca düzenleme için PDFKit'e bırak.
                    if event.clickCount == 2 && a.isWidget && a.widgetFieldType == .text {
                        s.select(nil)
                        super.mouseDown(with: event)
                        return
                    }
                    if event.clickCount == 2 && a.subtypeName == "Text" {
                        s.select(a)
                        s.editNote(a)
                        return
                    }
                    s.select(a)
                    if event.clickCount == 2 && a.isFreeText { s.requestTextFocus() }
                    drag = .move(a, page, a.bounds, pp)
                    return
                }
            }
            if s.selectedAnnotation != nil { s.select(nil) }
            if s.selectedTextItem != nil { s.selectTextItem(nil) }
            super.mouseDown(with: event)
        case .editText:
            guard let page = page(for: vp, nearest: false) else { return }
            let pp = convert(vp, to: page)
            if let a = topSelectableAnnotation(at: pp, on: page) {
                s.select(a)
                if event.clickCount == 2 && a.isFreeText { s.requestTextFocus() }
                drag = .move(a, page, a.bounds, pp)
                return
            }
            if s.selectedAnnotation != nil { s.select(nil) }
            let idx = s.document.index(for: page)
            guard idx != NSNotFound else { return }
            if let item = s.textItem(at: pp, pageIndex: idx) {
                s.selectTextItem(item)
                s.editNotice = nil
                beginInlineEdit(item: item, page: page, at: pp)
            } else {
                s.selectTextItem(nil)
                if s.textItems(onPage: idx).isEmpty {
                    s.editNotice = "Bu sayfada düzenlenebilir metin yok; sayfa taranmış olabilir. Önce Dönüştür > Tara ve OCR Uygula'yı kullanın. Yine de tıkladığınız yere yeni metin ekleyebilirsiniz."
                } else {
                    s.editNotice = nil
                }
                beginInlineEdit(item: nil, page: page, at: pp)
            }
        case .markup(let kind):
            markupPending = true
            super.mouseDown(with: event)
            // PDFView seçimi kendi döngüsünde bitirdiyse işaretlemeyi hemen uygula.
            if markupPending && (NSEvent.pressedMouseButtons & 1) == 0 {
                markupPending = false
                s.applyMarkup(kind)
            }
        case .ink:
            guard let page = page(for: vp, nearest: false) else { return }
            inkPagePoints = [convert(vp, to: page)]
            inkPreview = [vp]
            drag = .ink(page)
        default:
            guard let page = page(for: vp, nearest: false) else { return }
            s.place(at: convert(vp, to: page), on: page)
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard let s = session else { super.mouseDragged(with: event); return }
        let vp = convert(event.locationInWindow, from: nil)
        switch drag {
        case .none:
            super.mouseDragged(with: event)
        case .pan(let start, let origin):
            guard let sv = documentView?.enclosingScrollView else { return }
            let clip = sv.contentView
            let dx = event.locationInWindow.x - start.x
            let dy = event.locationInWindow.y - start.y
            var o = origin
            o.x -= dx
            o.y += clip.isFlipped ? dy : -dy
            let constrained = clip.constrainBoundsRect(NSRect(origin: o, size: clip.bounds.size))
            clip.scroll(to: constrained.origin)
            sv.reflectScrolledClipView(clip)
            didDrag = true
        case .move(let a, let page, let start, let startPt):
            let pp = convert(vp, to: page)
            a.bounds = start.offsetBy(dx: pp.x - startPt.x, dy: pp.y - startPt.y)
            didDrag = true
            s.liveBoundsChanged(a)
        case .resize(let a, let page, let start, let corner, let startPt):
            let pp = convert(vp, to: page)
            let dx = pp.x - startPt.x, dy = pp.y - startPt.y
            var r = start
            switch corner {
            case .bottomLeft:
                r = CGRect(x: start.minX + dx, y: start.minY + dy, width: start.width - dx, height: start.height - dy)
            case .bottomRight:
                r = CGRect(x: start.minX, y: start.minY + dy, width: start.width + dx, height: start.height - dy)
            case .topLeft:
                r = CGRect(x: start.minX + dx, y: start.minY, width: start.width - dx, height: start.height + dy)
            case .topRight:
                r = CGRect(x: start.minX, y: start.minY, width: start.width + dx, height: start.height + dy)
            }
            guard r.width >= 8, r.height >= 8 else { return }
            if a is ImageAnnotation, start.width > 0 {
                // Görsel ve imzalarda en-boy oranını koru.
                let ratio = start.height / start.width
                let newH = r.width * ratio
                if corner == .bottomLeft || corner == .bottomRight {
                    r.origin.y = start.maxY - newH
                }
                r.size.height = newH
            }
            a.bounds = r
            didDrag = true
            s.liveBoundsChanged(a)
        case .rect(_, let startV):
            dragRect = NSRect(x: min(startV.x, vp.x), y: min(startV.y, vp.y),
                              width: abs(vp.x - startV.x), height: abs(vp.y - startV.y))
            refreshOverlay()
        case .ink(let page):
            inkPagePoints.append(convert(vp, to: page))
            inkPreview?.append(vp)
            didDrag = true
            refreshOverlay()
        }
    }

    override func mouseUp(with event: NSEvent) {
        guard let s = session else { super.mouseUp(with: event); return }
        let mode = drag
        drag = .none
        switch mode {
        case .none:
            super.mouseUp(with: event)
            if markupPending, case .markup(let kind) = s.tool {
                markupPending = false
                s.applyMarkup(kind)
            }
        case .pan:
            NSCursor.openHand.set()
        case .move(let a, _, let start, _):
            if didDrag {
                s.commitBounds(a, from: start)
            } else if s.isOwnWidget(a) && a.widgetFieldType == .button {
                s.toggleButton(a)
            }
        case .resize(let a, _, let start, _, _):
            if didDrag {
                if a.isFreeText { s.fitFreeText(a) }
                s.commitBounds(a, from: start)
            }
        case .rect(let page, _):
            if let r = dragRect, r.width > 4, r.height > 4 {
                let pr = convert(r, to: page)
                dragRect = nil
                s.placeRect(pr, on: page)
            }
            dragRect = nil
        case .ink(let page):
            let pts = inkPagePoints
            inkPagePoints = []
            inkPreview = nil
            if pts.count > 1 { s.addInk(pts, on: page) }
        }
        refreshOverlay()
    }

    // MARK: - Klavye

    override func keyDown(with event: NSEvent) {
        if let s = session, let a = s.selectedAnnotation {
            let step: CGFloat = event.modifierFlags.contains(.shift) ? 10 : 1
            var delta: CGPoint?
            switch event.keyCode {
            case 51, 117:
                s.remove(a, name: "Sil")
                return
            case 53:
                s.select(nil)
                return
            case 123: delta = CGPoint(x: -step, y: 0)
            case 124: delta = CGPoint(x: step, y: 0)
            case 125: delta = CGPoint(x: 0, y: -step)
            case 126: delta = CGPoint(x: 0, y: step)
            default: break
            }
            if let d = delta {
                let old = a.bounds
                s.setBounds(a, to: old.offsetBy(dx: d.x, dy: d.y), from: old)
                return
            }
        }
        if let s = session, s.selectedTextItem != nil {
            switch event.keyCode {
            case 51, 117:
                s.deleteSelectedTextItem()
                return
            case 53:
                s.selectTextItem(nil)
                return
            default:
                break
            }
        }
        if event.keyCode == 53, let s = session, s.tool != .select {
            s.tool = .select
            dragRect = nil
            refreshOverlay()
            return
        }
        super.keyDown(with: event)
    }
}
