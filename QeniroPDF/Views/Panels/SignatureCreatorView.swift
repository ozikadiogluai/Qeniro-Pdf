import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// Yeni imza oluşturma: Çiz (trackpad/fare), Yaz (el yazısı fontu), Görsel (dosyadan).
struct SignatureCreatorView: View {
    enum Mode: String, CaseIterable, Identifiable {
        case draw = "Çiz", type = "Yaz", image = "Görsel"
        var id: String { rawValue }
    }

    @Environment(\.dismiss) private var dismiss
    let onCreate: (NSImage) -> Void

    /// `initialText` verilirse (ör. baş harfler) "Yaz" sekmesinde bu metinle açılır.
    init(initialText: String? = nil, onCreate: @escaping (NSImage) -> Void) {
        self.onCreate = onCreate
        _typed = State(initialValue: initialText ?? NSFullUserName())
        _mode = State(initialValue: initialText == nil ? .draw : .type)
    }

    @State private var mode: Mode = .draw
    @State private var strokes: [[CGPoint]] = []
    @State private var current: [CGPoint] = []
    @State private var typed = NSFullUserName()
    @State private var fontName = "Snell Roundhand"
    @State private var loaded: NSImage?
    @State private var removeWhite = true
    @State private var ink = Color(red: 0.08, green: 0.20, blue: 0.55)

    static let fonts = ["Snell Roundhand", "Apple Chancery", "Zapfino", "Bradley Hand", "Noteworthy", "Savoye LET"]
    let canvasSize = CGSize(width: 480, height: 180)

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Yeni İmza Oluştur").font(.title3.bold())
            Picker("", selection: $mode) {
                ForEach(Mode.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            ZStack {
                RoundedRectangle(cornerRadius: 8).fill(Color.white)
                switch mode {
                case .draw: drawCanvas
                case .type:
                    Text(typed.isEmpty ? "Adınız" : typed)
                        .font(.custom(fontName, size: 44))
                        .foregroundStyle(ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.3)
                        .padding(.horizontal, 16)
                case .image:
                    if let loaded {
                        Image(nsImage: removeWhite ? Self.removeWhiteBackground(loaded) : loaded)
                            .resizable().scaledToFit().padding(12)
                    } else {
                        Button("Görsel seç…") { pickImage() }
                    }
                }
            }
            .frame(width: canvasSize.width, height: canvasSize.height)
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.border))

            switch mode {
            case .draw:
                Text("Trackpad veya fare ile kutunun içine imzanızı çizin.").font(.caption).foregroundStyle(.secondary)
            case .type:
                HStack {
                    TextField("Adınız Soyadınız", text: $typed).textFieldStyle(.roundedBorder)
                    Picker("", selection: $fontName) {
                        ForEach(Self.fonts, id: \.self) { Text($0).font(.custom($0, size: 13)).tag($0) }
                    }
                    .labelsHidden()
                    .frame(width: 170)
                }
            case .image:
                HStack {
                    Button("Başka görsel seç…") { pickImage() }
                    Toggle("Beyaz arka planı kaldır", isOn: $removeWhite)
                }
            }

            HStack {
                if mode != .image {
                    ColorPicker("Mürekkep rengi", selection: $ink, supportsOpacity: false)
                }
                if mode == .draw {
                    Button("Temizle") { strokes = []; current = [] }
                        .disabled(strokes.isEmpty)
                }
                Spacer()
                Button("Vazgeç") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Kaydet ve Kullan") { save() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.selection)
                    .disabled(!canSave)
            }
        }
        .padding(20)
        .frame(width: canvasSize.width + 40)
    }

    private var canSave: Bool {
        switch mode {
        case .draw: return !strokes.isEmpty
        case .type: return !typed.trimmingCharacters(in: .whitespaces).isEmpty
        case .image: return loaded != nil
        }
    }

    private var drawCanvas: some View {
        ZStack(alignment: .bottomLeading) {
            Path { p in
                p.move(to: CGPoint(x: 30, y: canvasSize.height - 40))
                p.addLine(to: CGPoint(x: canvasSize.width - 30, y: canvasSize.height - 40))
            }
            .stroke(Color.gray.opacity(0.35), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
            if strokes.isEmpty && current.isEmpty {
                Text("Burada imzalayın")
                    .foregroundStyle(Color.gray.opacity(0.6))
                    .padding(.leading, 32)
                    .padding(.bottom, 46)
            }
            Canvas { ctx, _ in
                for s in strokes + [current] where !s.isEmpty {
                    var path = Path()
                    path.move(to: s[0])
                    if s.count == 1 { path.addLine(to: CGPoint(x: s[0].x + 0.5, y: s[0].y + 0.5)) }
                    for pt in s.dropFirst() { path.addLine(to: pt) }
                    ctx.stroke(path, with: .color(ink), style: StrokeStyle(lineWidth: 2.6, lineCap: .round, lineJoin: .round))
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { v in current.append(v.location) }
                    .onEnded { _ in
                        if !current.isEmpty { strokes.append(current) }
                        current = []
                    }
            )
        }
        .frame(width: canvasSize.width, height: canvasSize.height)
    }

    private func pickImage() {
        if let u = Dialogs.openFiles(types: [.image], multiple: false, title: "İmza görseli seçin").first {
            loaded = NSImage(contentsOf: u)
        }
    }

    private func save() {
        let color = NSColor(ink)
        var image: NSImage?
        switch mode {
        case .draw:
            let all = strokes.flatMap { $0 }
            guard let minX = all.map(\.x).min(), let maxX = all.map(\.x).max(),
                  let minY = all.map(\.y).min(), let maxY = all.map(\.y).max() else { return }
            let pad: CGFloat = 6
            let box = CGRect(x: minX - pad, y: minY - pad, width: max(maxX - minX, 1) + pad * 2, height: max(maxY - minY, 1) + pad * 2)
            let s = strokes
            image = Self.rasterize(size: box.size, scale: 3) {
                color.setStroke()
                for stroke in s where !stroke.isEmpty {
                    let p = NSBezierPath()
                    p.lineWidth = 2.6
                    p.lineCapStyle = .round
                    p.lineJoinStyle = .round
                    // SwiftUI üstten aşağı, AppKit alttan yukarı: y eksenini çevir.
                    func pt(_ c: CGPoint) -> NSPoint { NSPoint(x: c.x - box.minX, y: box.maxY - c.y) }
                    p.move(to: pt(stroke[0]))
                    if stroke.count == 1 { p.line(to: NSPoint(x: pt(stroke[0]).x + 0.5, y: pt(stroke[0]).y)) }
                    for c in stroke.dropFirst() { p.line(to: pt(c)) }
                    p.stroke()
                }
            }
        case .type:
            let font = NSFont(name: fontName, size: 72) ?? NSFont.systemFont(ofSize: 72)
            let attr = NSAttributedString(string: typed, attributes: [.font: font, .foregroundColor: color])
            let size = attr.size()
            let box = CGSize(width: ceil(size.width) + 16, height: ceil(size.height) + 12)
            image = Self.rasterize(size: box, scale: 2) {
                attr.draw(at: NSPoint(x: 8, y: 6))
            }
        case .image:
            if let loaded { image = removeWhite ? Self.removeWhiteBackground(loaded) : loaded }
        }
        if let image {
            onCreate(image)
            dismiss()
        }
    }

    /// Şeffaf arka planlı, yüksek çözünürlüklü bit eşlem üretir.
    static func rasterize(size: CGSize, scale: CGFloat, draw: () -> Void) -> NSImage? {
        let w = max(1, Int(size.width * scale)), h = max(1, Int(size.height * scale))
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: w, pixelsHigh: h,
                                         bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                         colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return nil }
        rep.size = NSSize(width: size.width, height: size.height)
        guard let ctx = NSGraphicsContext(bitmapImageRep: rep) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = ctx
        ctx.imageInterpolation = .high
        draw()
        ctx.flushGraphics()
        NSGraphicsContext.restoreGraphicsState()
        let img = NSImage(size: NSSize(width: size.width, height: size.height))
        img.addRepresentation(rep)
        return img
    }

    /// Neredeyse beyaz pikselleri şeffaf yapar (taranmış imzalar için).
    static func removeWhiteBackground(_ image: NSImage, threshold: UInt8 = 225) -> NSImage {
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return image }
        let w = cg.width, h = cg.height
        var pixels = [UInt8](repeating: 0, count: w * h * 4)
        let ok: Bool = pixels.withUnsafeMutableBytes { buf -> Bool in
            guard let ctx = CGContext(data: buf.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
            return true
        }
        guard ok else { return image }
        var i = 0
        while i < pixels.count {
            if pixels[i] >= threshold && pixels[i + 1] >= threshold && pixels[i + 2] >= threshold {
                pixels[i] = 0; pixels[i + 1] = 0; pixels[i + 2] = 0; pixels[i + 3] = 0
            }
            i += 4
        }
        let result: NSImage? = pixels.withUnsafeMutableBytes { buf -> NSImage? in
            guard let ctx = CGContext(data: buf.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
                  let out = ctx.makeImage() else { return nil }
            return NSImage(cgImage: out, size: image.size)
        }
        return result ?? image
    }
}
