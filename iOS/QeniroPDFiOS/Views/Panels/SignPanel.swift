import SwiftUI
import PencilKit
import PhotosUI

/// E-imza paneli: Çiz / Yaz / Görsel, kayıtlı imzalar, baş harfler, metin, onay, tarih ve
/// "İmzayı Kaydet ve Yerleştir".
struct SignPanel: View {
    @ObservedObject var session: DocumentSession
    @EnvironmentObject private var store: SignatureStore
    @Binding var detent: PresentationDetent

    enum Source: String, CaseIterable, Identifiable {
        case draw = "Çiz", type = "Yaz", image = "Görsel"
        var id: String { rawValue }
    }

    @State private var source: Source = .draw
    @State private var drawing = PKDrawing()
    @State private var typedName = ""
    @State private var fontIndex = 0
    @State private var pickedImage: UIImage?
    @State private var processedImage: UIImage?
    @State private var photoItem: PhotosPickerItem?
    @State private var removeWhite = true
    @State private var askInitials = false
    @State private var initialsText = ""
    @State private var inkChoice = 0

    let inks: [(String, UIColor)] = [
        ("Lacivert", UIColor(hex: 0x1F3F8F)), ("Siyah", UIColor(hex: 0x111111)), ("Mavi", UIColor(hex: 0x2D6BE4))
    ]
    let purple = Theme.purple

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                segmented
                switch source {
                case .draw: drawArea
                case .type: typeArea
                case .image: imageArea
                }
                chips
                if !store.signatures.isEmpty { savedList }
                PrimaryButton(title: "İmzayı Kaydet ve Yerleştir", color: purple) { saveAndPlace() }
                if session.redactionMarkCount > 0 || hasPlacedItems {
                    Text("Yerleştirdiğiniz öğeleri sürükleyerek taşıyın. Bitince üstteki Uygula ile sayfaya kalıcı olarak gömün.")
                        .font(.system(size: 12.5))
                        .foregroundStyle(Theme.secondary)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .background(Theme.card)
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self), let img = UIImage(data: data) {
                    pickedImage = img
                    reprocess()
                } else {
                    session.errorMessage = "Görsel yüklenemedi."
                }
                photoItem = nil
            }
        }
        .onChange(of: removeWhite) { _, _ in reprocess() }
        .alert("Baş harfler", isPresented: $askInitials) {
            TextField("Ör. A.Y.", text: $initialsText)
            Button("Kaydet ve Yerleştir") { placeInitials() }
            Button("Vazgeç", role: .cancel) {}
        } message: {
            Text("Baş harfleriniz el yazısı görünümünde kaydedilir.")
        }
    }

    private var hasPlacedItems: Bool {
        for i in 0..<session.document.pageCount {
            if session.document.page(at: i)?.annotations.contains(where: { $0 is ImageAnnotation }) == true { return true }
        }
        return false
    }

    private var segmented: some View {
        HStack(spacing: 0) {
            ForEach(Source.allCases) { s in
                Button { source = s } label: {
                    Text(s.rawValue)
                        .font(.system(size: 14, weight: source == s ? .semibold : .regular))
                        .foregroundStyle(source == s ? Theme.text : Theme.tertiary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 34)
                        .background {
                            if source == s {
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(Theme.card)
                                    .shadow(color: .black.opacity(0.08), radius: 1.5, x: 0, y: 1)
                            }
                        }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(Theme.segmentBackground, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var drawArea: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.padBackground)
            Rectangle()
                .fill(Theme.border)
                .frame(height: 1)
                .padding(.horizontal, 20)
                .frame(maxHeight: .infinity, alignment: .bottom)
                .padding(.bottom, 28)
            SignaturePadView(drawing: $drawing, inkColor: inks[inkChoice].1)
            VStack {
                HStack {
                    Menu {
                        ForEach(inks.indices, id: \.self) { i in
                            Button(inks[i].0) { inkChoice = i }
                        }
                    } label: {
                        Circle().fill(Color(uiColor: inks[inkChoice].1)).frame(width: 18, height: 18)
                            .frame(width: 32, height: 32)
                    }
                    .accessibilityLabel("Mürekkep rengi")
                    Spacer()
                    Button("Temizle") { drawing = PKDrawing() }
                        .font(.system(size: 13.5))
                        .foregroundStyle(Theme.blue)
                        .frame(height: 32)
                        .padding(.horizontal, 10)
                }
                Spacer()
                Text("Parmağınla veya Apple Pencil ile imzala")
                    .font(.system(size: 11.5))
                    .foregroundStyle(Theme.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, 20)
                    .padding(.bottom, 8)
                    .allowsHitTesting(false)
            }
            .padding(.top, 8)
            .padding(.trailing, 8)
            .padding(.leading, 8)
        }
        .frame(height: 150)
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Theme.border, lineWidth: 1))
    }

    private var typeArea: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField("Adınızı yazın", text: $typedName)
                .textFieldStyle(.roundedBorder)
                .textContentType(.name)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(SignatureImages.scriptFonts.indices, id: \.self) { i in
                        Button { fontIndex = i } label: {
                            Text(typedName.isEmpty ? "İmza" : typedName)
                                .font(.custom(SignatureImages.scriptFonts[i].name, size: 22))
                                .foregroundStyle(Color(uiColor: inks[inkChoice].1))
                                .lineLimit(1)
                                .padding(.horizontal, 12)
                                .frame(height: 56)
                                .background(fontIndex == i ? Theme.chipSelected : Theme.padBackground,
                                            in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .strokeBorder(fontIndex == i ? Theme.blue : Theme.border, lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .frame(minHeight: 150, alignment: .top)
    }

    private var imageArea: some View {
        VStack(alignment: .leading, spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.padBackground)
                if let img = processedImage {
                    Image(uiImage: img).resizable().scaledToFit().padding(12)
                } else {
                    Text("Beyaz kâğıda atılmış imzanızın fotoğrafını seçin.")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.secondary)
                        .multilineTextAlignment(.center)
                        .padding()
                }
            }
            .frame(height: 150)
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Theme.border, lineWidth: 1))
            HStack {
                PhotosPicker(selection: $photoItem, matching: .images) {
                    Label("Fotoğraf seç", systemImage: "photo").font(.system(size: 14))
                }
                Spacer()
                Toggle("Beyazı kaldır", isOn: $removeWhite).font(.system(size: 13.5)).fixedSize()
            }
        }
    }

    private func reprocess() {
        guard let pickedImage else { processedImage = nil; return }
        processedImage = removeWhite ? (Self.removingWhite(pickedImage) ?? pickedImage) : pickedImage
    }

    private var chips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                Chip(title: "Aa Baş harfler") { initialsText = ""; askInitials = true }
                Chip(title: "T Metin", selected: session.tool == .placeText) { session.tool = .placeText; detent = .height(220) }
                Chip(title: "✓ Onay", selected: session.tool == .placeCheck) { session.tool = .placeCheck; detent = .height(220) }
                Chip(title: "Tarih", selected: session.tool == .placeDate) { session.tool = .placeDate; detent = .height(220) }
            }
        }
    }

    private var savedList: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionLabel(text: "Kayıtlı imzalar")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(store.signatures) { sig in
                        Button {
                            session.tool = .placeSignature(sig.id)
                            detent = .height(220)
                        } label: {
                            Group {
                                if let img = store.image(for: sig.id) {
                                    Image(uiImage: img).resizable().scaledToFit()
                                } else {
                                    Image(systemName: "signature")
                                }
                            }
                            .padding(6)
                            .frame(width: 96, height: 52)
                            .background(Color.white, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .strokeBorder(session.tool == .placeSignature(sig.id) ? Theme.blue : Theme.border, lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button(role: .destructive) { store.delete(sig.id) } label: { Label("İmzayı sil", systemImage: "trash") }
                        }
                    }
                }
            }
        }
    }

    private func currentSignatureImage() -> UIImage? {
        let ink = inks[inkChoice].1
        switch source {
        case .draw: return SignatureImages.image(from: drawing)
        case .type: return SignatureImages.image(fromText: typedName, fontName: SignatureImages.scriptFonts[fontIndex].name, color: ink)
        case .image: return processedImage
        }
    }

    private func saveAndPlace() {
        guard let img = currentSignatureImage() else {
            session.infoMessage = source == .draw ? "Önce imza alanına imzanızı çizin."
                : source == .type ? "Önce adınızı yazın." : "Önce bir imza fotoğrafı seçin."
            return
        }
        guard let sig = store.add(img) else {
            session.errorMessage = "İmza kaydedilemedi."
            return
        }
        drawing = PKDrawing()
        session.tool = .placeSignature(sig.id)
        detent = .height(220)
    }

    private func placeInitials() {
        let fontName = SignatureImages.scriptFonts[fontIndex].name
        guard let img = SignatureImages.image(fromText: initialsText, fontName: fontName, color: inks[inkChoice].1),
              let sig = store.add(img, initials: true) else { return }
        session.tool = .placeSignature(sig.id)
        detent = .height(220)
    }

    /// Açık renkli pikselleri saydam yapar (beyaz kâğıttaki imza fotoğrafı için).
    static func removingWhite(_ image: UIImage) -> UIImage? {
        guard let cg = ImageAnnotation.makeCGImage(image) else { return nil }
        let maxSide: CGFloat = 1200
        let scale = min(1, maxSide / CGFloat(max(cg.width, cg.height)))
        let w = max(1, Int(CGFloat(cg.width) * scale)), h = max(1, Int(CGFloat(cg.height) * scale))
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let buf = ctx.data else { return nil }
        ctx.interpolationQuality = .high
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
        let p = buf.bindMemory(to: UInt8.self, capacity: w * h * 4)
        for i in 0..<(w * h) {
            let o = i * 4
            let r = Int(p[o]), g = Int(p[o + 1]), b = Int(p[o + 2])
            let lum = (r * 299 + g * 587 + b * 114) / 1000
            if lum > 200 {
                p[o] = 0; p[o + 1] = 0; p[o + 2] = 0; p[o + 3] = 0
            } else if lum > 150 {
                // Yumuşak geçiş: kenarları kırpık görünmesin.
                let a = UInt8(max(0, min(255, (200 - lum) * 255 / 50)))
                let k = Double(a) / 255
                p[o] = UInt8(Double(r) * k); p[o + 1] = UInt8(Double(g) * k); p[o + 2] = UInt8(Double(b) * k); p[o + 3] = a
            }
        }
        guard let out = ctx.makeImage() else { return nil }
        return UIImage(cgImage: out)
    }
}

/// Yuvarlak kenarlı küçük seçim düğmesi.
struct Chip: View {
    let title: String
    var selected = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13.5))
                .foregroundStyle(Theme.text)
                .padding(.horizontal, 12)
                .frame(height: 40)
                .background(selected ? Theme.chipSelected : Theme.card, in: Capsule())
                .overlay(Capsule().strokeBorder(selected ? Theme.blue : Theme.border, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}
