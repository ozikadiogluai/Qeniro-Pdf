import SwiftUI
import UIKit
import PDFKit
import Combine

/// PDFView'i SwiftUI'ye taşır; üzerine düzenleme kutuları, serbest çizim ve satır içi metin kutusu ekler.
struct PDFCanvas: UIViewRepresentable {
    @ObservedObject var session: DocumentSession

    func makeUIView(context: Context) -> PDFCanvasView {
        PDFCanvasView(session: session)
    }

    func updateUIView(_ view: PDFCanvasView, context: Context) {
        view.syncTool()
    }
}

/// Düzenleme kutularını, seçimi ve sürüklenen dikdörtgeni çizen, dokunmaları geçiren katman.
final class CanvasOverlayView: UIView {
    weak var canvas: PDFCanvasView?

    override init(frame: CGRect) {
        super.init(frame: frame)
        isOpaque = false
        backgroundColor = .clear
        isUserInteractionEnabled = false
        contentMode = .redraw
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) kullanılmaz") }

    override func draw(_ rect: CGRect) {
        canvas?.drawOverlay(in: self)
    }
}

/// Parmak veya Apple Pencil ile serbest çizim toplar.
final class InkCaptureView: UIView {
    var onStroke: (([CGPoint]) -> Void)?
    var strokeColor: UIColor = .systemRed { didSet { shape.strokeColor = strokeColor.cgColor } }
    private var points: [CGPoint] = []
    private let shape = CAShapeLayer()

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isMultipleTouchEnabled = false
        shape.fillColor = nil
        shape.lineWidth = 2.5
        shape.lineCap = .round
        shape.lineJoin = .round
        shape.strokeColor = strokeColor.cgColor
        layer.addSublayer(shape)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) kullanılmaz") }

    override func layoutSubviews() {
        super.layoutSubviews()
        shape.frame = bounds
    }

    private func updatePath() {
        let path = UIBezierPath()
        if let f = points.first {
            path.move(to: f)
            for p in points.dropFirst() { path.addLine(to: p) }
        }
        shape.path = path.cgPath
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let t = touches.first else { return }
        points = [t.location(in: self)]
        updatePath()
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let t = touches.first else { return }
        // Apple Pencil'in ara örneklerini de kullan (daha düzgün çizgi).
        let samples = event?.coalescedTouches(for: t) ?? [t]
        for s in samples { points.append(s.location(in: self)) }
        updatePath()
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        if let t = touches.first { points.append(t.location(in: self)) }
        let done = points
        points = []
        shape.path = nil
        if done.count > 1 { onStroke?(done) }
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        points = []
        shape.path = nil
    }
}

/// PDFView + katmanlar. Tüm araç hareketleri burada sayfa koordinatlarına çevrilir.
final class PDFCanvasView: UIView, UIGestureRecognizerDelegate, UITextFieldDelegate {
    let session: DocumentSession
    var pdfView: PDFView { session.pdfView }
    private let overlay = CanvasOverlayView()
    private let inkView = InkCaptureView()
    private let field = UITextField()
    private var tap: UITapGestureRecognizer!
    private var pan: UIPanGestureRecognizer!
    private var displayLink: CADisplayLink?
    private var lastSignature: [CGFloat] = []
    private var cancellables: Set<AnyCancellable> = []
    private var observers: [NSObjectProtocol] = []

    // Sürükleme durumu
    private var dragAnnotation: PDFAnnotation?
    private var dragStartBounds: CGRect = .zero
    private var dragStartPoint: CGPoint = .zero
    private var rectPage: PDFPage?
    private var rectStart: CGPoint = .zero
    private var rectCurrent: CGRect?

    // Satır içi düzenleme
    private var fieldPage: PDFPage?
    private var fieldPageRect: CGRect = .zero
    private var fieldFontSize: CGFloat = 12
    private var finishing = false

    init(session: DocumentSession) {
        self.session = session
        super.init(frame: .zero)
        backgroundColor = .clear
        let pv = session.pdfView
        pv.translatesAutoresizingMaskIntoConstraints = true
        pv.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        pv.frame = bounds
        addSubview(pv)

        overlay.canvas = self
        overlay.frame = bounds
        overlay.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        addSubview(overlay)

        inkView.frame = bounds
        inkView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        inkView.isHidden = true
        inkView.onStroke = { [weak self] pts in self?.finishStroke(pts) }
        addSubview(inkView)

        field.isHidden = true
        field.delegate = self
        field.borderStyle = .none
        field.backgroundColor = UIColor.white
        field.textColor = .black
        field.layer.borderColor = UIColor(red: 0.176, green: 0.42, blue: 0.894, alpha: 1).cgColor
        field.layer.borderWidth = 1.5
        field.layer.cornerRadius = 2
        field.returnKeyType = .done
        field.autocorrectionType = .no
        field.spellCheckingType = .no
        field.overrideUserInterfaceStyle = .light
        field.addTarget(self, action: #selector(fieldChanged), for: .editingChanged)
        addSubview(field)

        tap = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        tap.delegate = self
        tap.cancelsTouchesInView = false
        pv.addGestureRecognizer(tap)

        pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        pan.delegate = self
        pan.maximumNumberOfTouches = 1
        pv.addGestureRecognizer(pan)

        let nc = NotificationCenter.default
        observers.append(nc.addObserver(forName: .qeniroOverlayNeedsRefresh, object: session, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.overlay.setNeedsDisplay() }
        })
        observers.append(nc.addObserver(forName: .qeniroCommitInline, object: session, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.commitField() }
        })
        observers.append(nc.addObserver(forName: UIResponder.keyboardWillChangeFrameNotification, object: nil, queue: .main) { [weak self] n in
            let end = (n.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue)?.cgRectValue
            MainActor.assumeIsolated { self?.keyboardChanged(end) }
        })

        session.$inlineTarget
            .receive(on: RunLoop.main)
            .sink { [weak self] target in self?.showField(for: target) }
            .store(in: &cancellables)
        session.$inkColor
            .sink { [weak self] c in self?.inkView.strokeColor = c }
            .store(in: &cancellables)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) kullanılmaz") }

    deinit {
        for o in observers { NotificationCenter.default.removeObserver(o) }
        displayLink?.invalidate()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window != nil {
            if displayLink == nil {
                let link = CADisplayLink(target: DisplayLinkProxy(self), selector: #selector(DisplayLinkProxy.tick))
                link.preferredFrameRateRange = CAFrameRateRange(minimum: 15, maximum: 30, preferred: 30)
                link.add(to: .main, forMode: .common)
                displayLink = link
            }
            // Kaydırma hareketi, öğe sürükleme hareketimiz başarısız olursa başlasın.
            if let scroll = Self.findScrollView(in: pdfView) {
                scroll.panGestureRecognizer.require(toFail: pan)
            }
            syncTool()
        } else {
            displayLink?.invalidate()
            displayLink = nil
        }
    }

    static func findScrollView(in view: UIView) -> UIScrollView? {
        for v in view.subviews {
            if let s = v as? UIScrollView { return s }
            if let s = findScrollView(in: v) { return s }
        }
        return nil
    }

    func syncTool() {
        let drawing = session.tool == .draw
        inkView.isHidden = !drawing
        inkView.isUserInteractionEnabled = drawing
        overlay.setNeedsDisplay()
    }

    /// Kaydırma/yakınlaştırma değişince katmanları yeniden konumlandırır.
    fileprivate func tick() {
        var sig: [CGFloat] = [pdfView.scaleFactor]
        if let p = pdfView.visiblePages.first {
            let o = pdfView.convert(CGPoint.zero, from: p)
            sig.append(o.x); sig.append(o.y)
        }
        if sig != lastSignature {
            lastSignature = sig
            overlay.setNeedsDisplay()
            layoutField()
        }
    }

    // MARK: - Dönüşümler

    private func viewRect(_ r: CGRect, on page: PDFPage) -> CGRect {
        convert(pdfView.convert(r, from: page), from: pdfView)
    }

    private func pagePoint(_ gr: UIGestureRecognizer, nearest: Bool = false) -> (PDFPage, CGPoint)? {
        let pt = gr.location(in: pdfView)
        guard let page = pdfView.page(for: pt, nearest: nearest) else { return nil }
        return (page, pdfView.convert(pt, to: page))
    }

    // MARK: - Hareketler

    func gestureRecognizer(_ g: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
        g === tap
    }

    override func gestureRecognizerShouldBegin(_ g: UIGestureRecognizer) -> Bool {
        if g === pan {
            if session.tool.isRectTool { return true }
            guard session.tool == .select, session.inlineTarget == nil, let hit = pagePoint(g) else { return false }
            let page = hit.0, p = hit.1
            if let sel = session.selectedAnnotation, sel.page === page, session.isMovable(sel),
               sel.bounds.insetBy(dx: -10, dy: -10).contains(p) {
                return true
            }
            return page.annotations.contains { a in
                session.isMovable(a) && a.bounds.insetBy(dx: -4, dy: -4).contains(p)
            }
        }
        return super.gestureRecognizerShouldBegin(g)
    }

    @objc private func handleTap(_ gr: UITapGestureRecognizer) {
        guard gr.state == .ended else { return }
        if !field.isHidden {
            // Dışarı dokunmak düzenlemeyi uygular.
            let loc = gr.location(in: self)
            if field.frame.contains(loc) { return }
            commitField()
            if session.tool != .editText { return }
        }
        guard session.tool != .draw, !session.tool.isRectTool else { return }
        guard let hit = pagePoint(gr) else {
            if session.tool == .select { session.select(nil) }
            return
        }
        let page = hit.0, p = hit.1
        // Seç aracında bağlantı vb. PDFView'in kendi davranışına bırakılır; yalnızca kendi öğelerimiz seçilir.
        session.place(at: p, on: page)
    }

    @objc private func handlePan(_ gr: UIPanGestureRecognizer) {
        if session.tool.isRectTool {
            handleRectPan(gr)
            return
        }
        switch gr.state {
        case .began:
            guard let hit = pagePoint(gr) else { return }
            let page = hit.0, p = hit.1
            var target: PDFAnnotation?
            if let sel = session.selectedAnnotation, sel.page === page, sel.bounds.insetBy(dx: -10, dy: -10).contains(p) {
                target = sel
            } else {
                target = page.annotations.last { session.isMovable($0) && $0.bounds.insetBy(dx: -4, dy: -4).contains(p) }
            }
            guard let target else { return }
            dragAnnotation = target
            dragStartBounds = target.bounds
            dragStartPoint = p
            session.select(target)
        case .changed:
            guard let a = dragAnnotation, let page = a.page else { return }
            let pt = gr.location(in: pdfView)
            let p = pdfView.convert(pt, to: page)
            let r = dragStartBounds.offsetBy(dx: p.x - dragStartPoint.x, dy: p.y - dragStartPoint.y)
            session.liveMove(a, to: r)
        case .ended:
            if let a = dragAnnotation, a.bounds != dragStartBounds {
                session.setBounds(a, to: a.bounds, from: dragStartBounds)
            }
            dragAnnotation = nil
        default:
            if let a = dragAnnotation { session.liveMove(a, to: dragStartBounds) }
            dragAnnotation = nil
        }
    }

    private func handleRectPan(_ gr: UIPanGestureRecognizer) {
        switch gr.state {
        case .began:
            guard let hit = pagePoint(gr, nearest: true) else { return }
            rectPage = hit.0
            rectStart = hit.1
            let p = hit.1
            rectCurrent = CGRect(origin: p, size: .zero)
        case .changed:
            guard let page = rectPage else { return }
            let p = pdfView.convert(gr.location(in: pdfView), to: page)
            rectCurrent = CGRect(x: min(p.x, rectStart.x), y: min(p.y, rectStart.y),
                                 width: abs(p.x - rectStart.x), height: abs(p.y - rectStart.y))
            overlay.setNeedsDisplay()
        case .ended:
            if let page = rectPage, let r = rectCurrent { session.placeRect(r, on: page) }
            rectPage = nil
            rectCurrent = nil
            overlay.setNeedsDisplay()
        default:
            rectPage = nil
            rectCurrent = nil
            overlay.setNeedsDisplay()
        }
    }

    private func finishStroke(_ pts: [CGPoint]) {
        guard let first = pts.first else { return }
        let firstInPDF = inkView.convert(first, to: pdfView)
        guard let page = pdfView.page(for: firstInPDF, nearest: true) else { return }
        let mapped = pts.map { pdfView.convert(inkView.convert($0, to: pdfView), to: page) }
        session.addInk(mapped, on: page, lineWidth: max(1.2, 2.5 / max(pdfView.scaleFactor, 0.2)))
    }

    // MARK: - Katman çizimi

    func drawOverlay(in view: UIView) {
        let blue = UIColor(red: 0.176, green: 0.42, blue: 0.894, alpha: 1)
        let dashed = UIColor(red: 0.616, green: 0.722, blue: 0.933, alpha: 1)
        if session.tool == .editText {
            for page in pdfView.visiblePages {
                let idx = session.document.index(for: page)
                guard idx >= 0, idx != NSNotFound else { continue }
                for item in session.textItems(onPage: idx) {
                    let r = viewRect(item.bounds, on: page).insetBy(dx: -2, dy: -2)
                    if let sel = session.selectedTextItem, sel == item {
                        drawSelection(r, color: blue)
                    } else {
                        let path = UIBezierPath(rect: r)
                        path.lineWidth = 1
                        path.setLineDash([3, 2], count: 2, phase: 0)
                        dashed.setStroke()
                        path.stroke()
                    }
                }
            }
        }
        if let a = session.selectedAnnotation, let page = a.page {
            drawSelection(viewRect(a.bounds, on: page).insetBy(dx: -3, dy: -3), color: blue)
        }
        if let r = rectCurrent, let page = rectPage {
            let vr = viewRect(r, on: page)
            let path = UIBezierPath(rect: vr)
            path.lineWidth = 1.5
            path.setLineDash([5, 3], count: 2, phase: 0)
            let c: UIColor = session.tool == .redact ? .black : blue
            c.withAlphaComponent(0.12).setFill()
            path.fill()
            c.setStroke()
            path.stroke()
        }
    }

    private func drawSelection(_ r: CGRect, color: UIColor) {
        let path = UIBezierPath(roundedRect: r, cornerRadius: 2)
        color.withAlphaComponent(0.06).setFill()
        path.fill()
        path.lineWidth = 1.5
        color.setStroke()
        path.stroke()
        for c in [CGPoint(x: r.minX, y: r.minY), CGPoint(x: r.maxX, y: r.minY),
                  CGPoint(x: r.minX, y: r.maxY), CGPoint(x: r.maxX, y: r.maxY)] {
            let h = UIBezierPath(ovalIn: CGRect(x: c.x - 4, y: c.y - 4, width: 8, height: 8))
            UIColor.white.setFill()
            h.fill()
            h.lineWidth = 1.5
            color.setStroke()
            h.stroke()
        }
    }

    // MARK: - Satır içi düzenleme kutusu

    private func showField(for target: InlineTarget?) {
        guard let target else {
            if !field.isHidden && !finishing {
                field.isHidden = true
                field.resignFirstResponder()
            }
            return
        }
        let scale = pdfView.scaleFactor
        switch target {
        case .pdfText(let item):
            guard let page = session.document.page(at: item.pageIndex) else { return }
            fieldPage = page
            fieldPageRect = item.bounds
            fieldFontSize = item.visualSize
            field.text = item.text
            field.textColor = item.color.withAlphaComponent(1)
            field.font = Self.font(family: item.familyName, bold: item.bold, italic: item.italic, size: item.visualSize * scale)
            pdfView.go(to: item.bounds.insetBy(dx: -20, dy: -40), on: page)
        case .newText(let idx, let topLeft):
            guard let page = session.document.page(at: idx) else { return }
            let st = session.textStyle
            fieldPage = page
            fieldFontSize = st.size
            fieldPageRect = CGRect(x: topLeft.x, y: topLeft.y - st.size * 1.3, width: max(120, st.size * 8), height: st.size * 1.3)
            field.text = ""
            field.textColor = st.uiColor
            field.font = st.makeFont(scale: scale)
        case .annotation(let a):
            guard let page = a.page else { return }
            fieldPage = page
            fieldPageRect = a.bounds
            let f = a.font ?? UIFont.systemFont(ofSize: 12)
            fieldFontSize = f.pointSize
            field.text = a.contents
            field.textColor = a.fontColor ?? .black
            field.font = f.withSize(f.pointSize * scale)
        }
        field.isHidden = false
        finishing = false
        session.pendingInlineText = field.text
        layoutField()
        field.becomeFirstResponder()
        field.selectAll(nil)
    }

    static func font(family: String, bold: Bool, italic: Bool, size: CGFloat) -> UIFont {
        var traits: UIFontDescriptor.SymbolicTraits = []
        if bold { traits.insert(.traitBold) }
        if italic { traits.insert(.traitItalic) }
        let base = UIFontDescriptor(fontAttributes: [.family: family])
        let d = base.withSymbolicTraits(traits) ?? base
        return UIFont(descriptor: d, size: max(4, size))
    }

    private func layoutField() {
        guard !field.isHidden, let page = fieldPage else { return }
        let scale = pdfView.scaleFactor
        if let f = field.font, abs(f.pointSize - fieldFontSize * scale) > 0.5 {
            field.font = f.withSize(max(4, fieldFontSize * scale))
        }
        var r = viewRect(fieldPageRect, on: page).insetBy(dx: -4, dy: -3)
        let textWidth = ((field.text ?? "") as NSString).size(withAttributes: [.font: field.font ?? UIFont.systemFont(ofSize: 12)]).width
        r.size.width = max(r.width, min(textWidth + 24, bounds.width - 16))
        r.size.height = max(r.height, (field.font?.lineHeight ?? 14) + 8)
        if r.maxX > bounds.maxX - 8 { r.origin.x = max(8, bounds.maxX - 8 - r.width) }
        field.frame = r
    }

    @objc private func fieldChanged() {
        session.pendingInlineText = field.text
        layoutField()
    }

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        commitField()
        return false
    }

    func textFieldDidEndEditing(_ textField: UITextField) {
        commitField()
    }

    /// Kutudaki metni belgeye uygular (bir kez).
    func commitField() {
        guard !field.isHidden, !finishing, session.inlineTarget != nil else { return }
        finishing = true
        let text = field.text ?? ""
        field.isHidden = true
        field.resignFirstResponder()
        session.finishInline(text)
        finishing = false
        overlay.setNeedsDisplay()
    }

    private func keyboardChanged(_ end: CGRect?) {
        guard !field.isHidden, let window, let end,
              let scroll = Self.findScrollView(in: pdfView) else { return }
        let kb = convert(end, from: window.screen.coordinateSpace)
        let overlap = field.frame.maxY + 16 - kb.minY
        if overlap > 0 {
            var o = scroll.contentOffset
            o.y += overlap
            scroll.setContentOffset(o, animated: true)
        }
    }
}

/// CADisplayLink hedefini zayıf tutar (görünüm serbest kalabilsin).
private final class DisplayLinkProxy: NSObject {
    weak var target: PDFCanvasView?
    init(_ t: PDFCanvasView) { target = t }
    @objc func tick() { target?.tick() }
}
