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
    @State private var confirmApply = false

    let inks: [(String, UIColor)] = [
        ("Lacivert", UIColor(hex: 0x2E4A5E)), ("Siyah", UIColor(hex: 0x121A21)), ("Mavi", UIColor(hex: 0x1F3F8F))
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                SheetHeader(title: "İmzala", primaryTitle: "Uygula",
                            onCancel: { session.cancelMode() },
                            onPrimary: { confirmApply = true })
                segmented
                switch source {
                case .draw: drawArea
                case .type: typeArea
                case .image: imageArea
                }
                savedList
                chips
                Button { saveAndPlace() } label: {
                    Label("İmzayı Kaydet ve Yerleştir", systemImage: "signature")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.text)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 48)
                        .background(Theme.card, in: Capsule())
                }
                .buttonStyle(.plain)
                if session.redactionMarkCount > 0 || hasPlacedItems {
                    Text("Yerleştirdiğiniz öğeleri sürükleyerek taşıyın. Bitince Uygula ile sayfaya kalıcı olarak gömün.")
                        .font(.footnote)
                        .foregroundStyle(Theme.secondary)
                        .padding(.horizontal, 4)
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 14)
            .padding(.bottom, 24)
        }
        .background(Theme.background)
        .confirmationDialog("İmzalar ve alanlar sayfaya gömülsün mü?", isPresented: $confirmApply, titleVisibility: .visible) {
            Button("Uygula ve kaydet") {
                let n = session.applyAnnotations()
                session.exitMode()
                if n > 0 { _ = session.save() }
            }
            Button("Yalnızca uygula") {
                _ = session.applyAnnotations()
                session.exitMode()
            }
            Button("Vazgeç", role: .cancel) {}
        } message: {
            Text("Uygulanan imza, metin, onay ve tarih öğeleri artık taşınamaz; belgenin parçası olur.")
        }
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
            ForEach(Source.allCases) { src in
                Button { source = src } label: {
                    Text(src.rawValue)
                        .font(.subheadline.weight(source == src ? .semibold : .regular))
                        .foregroundStyle(source == src ? Theme.onInk : Theme.text)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 40)
                        .background(source == src ? Theme.ink : Color.clear, in: Capsule())
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(source == src ? .isSelected : [])
            }
        }
        .padding(4)
        .background(Theme.card, in: Capsule())
    }

    private var drawArea: some View {
        ZStack {
            RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous).fill(Color.white)
            Rectangle()
                .fill(Color(hex: 0xDCDCD8))
                .frame(height: 1)
                .padding(.horizontal, 22)
                .frame(maxHeight: .infinity, alignment: .bottom)
                .padding(.bottom, 34)
            SignaturePadView(drawing: $drawing, inkColor: inks[inkChoice].1)
            VStack {
                HStack {
                    Menu {
                        ForEach(inks.indices, id: \.self) { i in
                            Button(inks[i].0) { inkChoice = i }
                        }
                    } label: {
                        Circle().fill(Color(uiColor: inks[inkChoice].1)).frame(width: 18, height: 18)
                            .frame(width: 44, height: 44)
                    }
                    .accessibilityLabel("Mürekkep rengi")
                    Spacer()
                    Button { drawing = PKDrawing() } label: {
                        Text("Temizle")
                            .font(.footnote)
                            .foregroundStyle(Color(hex: 0x111111))
                            .padding(.horizontal, 12)
                            .frame(height: 32)
                            .background(Color(hex: 0xF1F1EF), in: Capsule())
                            .frame(minHeight: 44)
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
                Text("Parmağınla veya Apple Pencil ile imzala")
                    .font(.caption)
                    .foregroundStyle(Color(hex: 0x6E6E6E))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, 14)
                    .padding(.bottom, 8)
                    .allowsHitTesting(false)
            }
            .padding(.horizontal, 8)
            .padding(.top, 2)
        }
        .frame(height: 170)
    }

    private var typeArea: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField("Adınızı yazın", text: $typedName)
                .textContentType(.name)
                .font(.subheadline)
                .padding(.horizontal, 14)
                .frame(minHeight: 44)
                .background(Theme.card2, in: Capsule())
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
                                .background(Color.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .strokeBorder(fontIndex == i ? Color(hex: 0x121A21) : Color(hex: 0xEDEDEB), lineWidth: fontIndex == i ? 1.5 : 1))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(SignatureImages.scriptFonts[i].title)
                    }
                }
            }
        }
        .padding(12)
        .frame(minHeight: 170, alignment: .top)
        .card()
    }

    private var imageArea: some View {
        VStack(alignment: .leading, spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.white)
                if let img = processedImage {
                    Image(uiImage: img).resizable().scaledToFit().padding(12)
                } else {
                    Text("Beyaz kâğıda atılmış imzanızın fotoğrafını seçin.")
                        .font(.footnote)
                        .foregroundStyle(Color(hex: 0x6E6E6E))
                        .multilineTextAlignment(.center)
                        .padding()
                }
            }
            .frame(height: 130)
            HStack {
                PhotosPicker(selection: $photoItem, matching: .images) {
                    Label("Fotoğraf seç", systemImage: "photo")
                        .font(.subheadline)
                        .foregroundStyle(Theme.text)
                        .padding(.horizontal, 14)
                        .frame(minHeight: 40)
                        .background(Theme.card2, in: Capsule())
                }
                Spacer()
                Toggle("Beyazı kaldır", isOn: $removeWhite).font(.footnote).fixedSize()
            }
        }
        .padding(12)
        .card()
    }

    private func reprocess() {
        guard let pickedImage else { processedImage = nil; return }
        processedImage = removeWhite ? (Self.removingWhite(pickedImage) ?? pickedImage) : pickedImage
    }

    private var chips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                Chip(title: "Metin", selected: session.tool == .placeText) { session.tool = .placeText; detent = .height(220) }
                Chip(title: "Onay kutusu", selected: session.tool == .placeCheck) { session.tool = .placeCheck; detent = .height(220) }
                Chip(title: "Tarih", selected: session.tool == .placeDate) { session.tool = .placeDate; detent = .height(220) }
            }
        }
    }

    private var savedList: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Kayıtlı imzalar")
                .font(.footnote)
                .foregroundStyle(Theme.secondary)
                .padding(.leading, 2)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(store.signatures) { sig in
                        let active = session.tool == .placeSignature(sig.id)
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
                            .background(Color.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .strokeBorder(active ? Color(hex: 0x121A21) : Color(hex: 0xEDEDEB), lineWidth: active ? 1.5 : 1))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Kayıtlı imza")
                        .accessibilityAddTraits(active ? .isSelected : [])
                        .contextMenu {
                            Button(role: .destructive) { store.delete(sig.id) } label: { Label("İmzayı sil", systemImage: "trash") }
                        }
                    }
                    Button { initialsText = ""; askInitials = true } label: {
                        Text("Aa")
                            .font(.custom("TimesNewRomanPS-ItalicMT", size: 20))
                            .foregroundStyle(Theme.ink)
                            .frame(width: 72, height: 52)
                            .background(Theme.card2, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Baş harfler")
                    Button { saveAndPlace() } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(Theme.ink)
                            .frame(width: 52, height: 52)
                            .background(Theme.card2, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Çizilen imzayı kaydet ve yerleştir")
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .card()
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

/// Kapsül seçim düğmesi (beyaz; seçiliyken koyu).
struct Chip: View {
    let title: String
    var selected = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.footnote)
                .foregroundStyle(selected ? Theme.onInk : Theme.text)
                .padding(.horizontal, 14)
                .frame(minHeight: 44)
                .background(selected ? Theme.ink : Theme.card, in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
