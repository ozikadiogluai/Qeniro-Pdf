import SwiftUI
import PhotosUI
import PDFKit

/// Belge verisini gerektiğinde (görünüm açılınca) hazırlayıp içeriğe veren sarmalayıcı.
struct SessionDataView<Content: View>: View {
    @ObservedObject var session: DocumentSession
    @ViewBuilder var content: (Data) -> Content
    @State private var data: Data?
    @State private var failed = false

    var body: some View {
        Group {
            if let data {
                content(data)
            } else if failed {
                Text("Belge hazırlanamadı.").foregroundStyle(Theme.accent)
            } else {
                ProgressView().frame(maxWidth: .infinity).padding()
            }
        }
        .task {
            session.commitInlineIfNeeded()
            if let d = session.currentData() { data = d } else { failed = true }
        }
    }
}

/// Alt paneldeki form sayfası çerçevesi (kaydırılabilir, kenar boşluklu).
struct PanelPage<Content: View>: View {
    let title: String
    @ViewBuilder var content: () -> Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) { content() }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
        }
        .background(Theme.card)
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Düzenle paneli: metin biçimi, içerik ekle, sayfayı değiştir.
struct EditPanel: View {
    @ObservedObject var session: DocumentSession
    @Binding var detent: PresentationDetent
    @State private var photoItem: PhotosPickerItem?
    @State private var confirmDeletePage = false

    let colors: [(String, Color)] = [
        ("Siyah", Color(hex: 0x111111)), ("Koyu gri", Color(hex: 0x555555)), ("Kırmızı", Color(hex: 0xD0271F)),
        ("Mavi", Color(hex: 0x1F4FB8)), ("Yeşil", Color(hex: 0x1E7E34)), ("Beyaz", .white)
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if !PDFiumSupport.isAvailable {
                        Label("Gerçek metin düzenleme motoru (PDFium) bu derlemede yok. Mac'te build-ios.sh ile yeniden derleyin.",
                              systemImage: "exclamationmark.triangle")
                            .font(.system(size: 12.5))
                            .foregroundStyle(Theme.accent)
                    }
                    styleRow
                    if session.selectedTextItem != nil || (session.selectedAnnotation?.isFreeText ?? false) {
                        HStack(spacing: 8) {
                            Button {
                                if session.selectedTextItem != nil { session.deleteSelectedTextItem() } else { session.deleteSelected() }
                            } label: {
                                Label("Seçili metni sil", systemImage: "trash").font(.system(size: 13.5))
                            }
                            .buttonStyle(.bordered)
                            .tint(Theme.accent)
                            Toggle(isOn: Binding(get: { session.textStyle.underline },
                                                 set: { v in session.updateStyle { $0.underline = v } })) {
                                Text("Altı çizili").font(.system(size: 13.5))
                            }
                            .toggleStyle(.button)
                        }
                    }

                    SectionLabel(text: "İçerik ekle")
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(minimum: 0), spacing: 6), count: 5), spacing: 6) {
                        AddTile(title: "Metin", icon: "textformat", selected: session.tool == .editText) {
                            session.tool = .editText
                        }
                        PhotosPicker(selection: $photoItem, matching: .images) {
                            AddTileLabel(title: "Görüntü", icon: "photo", selected: session.tool == .addImage)
                        }
                        .buttonStyle(.plain)
                        NavigationLink {
                            HeaderFooterForm(session: session)
                        } label: {
                            AddTileLabel(title: "Üst/Alt", icon: "rectangle.topthird.inset.filled", selected: false)
                        }
                        .buttonStyle(.plain)
                        NavigationLink {
                            WatermarkForm(session: session)
                        } label: {
                            AddTileLabel(title: "Filigran", icon: "drop", selected: false)
                        }
                        .buttonStyle(.plain)
                        AddTile(title: "Bağlantı", icon: "link", selected: session.tool == .link) {
                            session.tool = .link
                            detent = .height(220)
                        }
                    }

                    SectionLabel(text: "Sayfayı değiştir")
                    HStack(spacing: 6) {
                        SquareIconButton(icon: "arrow.clockwise", label: "Döndür") { session.rotateCurrent(by: 90) }
                        SquareIconButton(icon: "crop", label: "Kırp", selected: session.tool == .crop) {
                            session.tool = .crop
                            detent = .height(220)
                        }
                        SquareIconButton(icon: "trash", label: "Sayfayı sil") { confirmDeletePage = true }
                        Button {
                            session.openOrganizer()
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "square.grid.2x2").font(.system(size: 16))
                                Text("Sayfaları organize et").font(.system(size: 14)).lineLimit(1).minimumScaleFactor(0.8)
                            }
                            .foregroundStyle(Theme.text)
                            .frame(maxWidth: .infinity)
                            .frame(height: 44)
                            .background(Theme.card, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Theme.border, lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
            .background(Theme.card)
            .toolbar(.hidden, for: .navigationBar)
        }
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self), let img = UIImage(data: data) {
                    session.pendingImage = img
                    session.tool = .addImage
                    detent = .height(220)
                } else {
                    session.errorMessage = "Görüntü yüklenemedi."
                }
                photoItem = nil
            }
        }
        .confirmationDialog("Sayfa \(session.currentPageIndex + 1) silinsin mi?", isPresented: $confirmDeletePage, titleVisibility: .visible) {
            Button("Sayfayı sil", role: .destructive) { session.deletePages([session.currentPageIndex]) }
            Button("Vazgeç", role: .cancel) {}
        }
    }

    private var styleRow: some View {
        HStack(spacing: 6) {
            Menu {
                Picker("Yazı tipi", selection: Binding(get: { session.textStyle.family },
                                                      set: { v in session.updateStyle { $0.family = v } })) {
                    ForEach(familyChoices, id: \.self) { Text($0).tag($0) }
                }
            } label: {
                HStack {
                    Text(session.textStyle.family).font(.system(size: 14)).lineLimit(1)
                    Spacer(minLength: 2)
                    Image(systemName: "chevron.up.chevron.down").font(.system(size: 11))
                }
                .foregroundStyle(Theme.text)
                .padding(.horizontal, 10)
                .frame(maxWidth: .infinity, minHeight: 40)
                .background(Theme.card, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Theme.border, lineWidth: 1))
            }
            Menu {
                Picker("Boyut", selection: Binding(get: { session.textStyle.size },
                                                  set: { v in session.updateStyle { $0.size = v } })) {
                    ForEach(sizeChoices, id: \.self) { Text(Self.sizeText($0)).tag($0) }
                }
            } label: {
                HStack(spacing: 2) {
                    Text(Self.sizeText(session.textStyle.size)).font(.system(size: 14))
                    Image(systemName: "chevron.up.chevron.down").font(.system(size: 10))
                }
                .foregroundStyle(Theme.text)
                .frame(width: 64, height: 40)
                .background(Theme.card, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Theme.border, lineWidth: 1))
            }
            StyleToggle(label: "B", selected: session.textStyle.bold, bold: true) {
                session.updateStyle { $0.bold.toggle() }
            }
            .accessibilityLabel("Kalın")
            StyleToggle(label: "I", selected: session.textStyle.italic, italic: true) {
                session.updateStyle { $0.italic.toggle() }
            }
            .accessibilityLabel("İtalik")
            Menu {
                ForEach(colors, id: \.0) { c in
                    Button(c.0) { session.updateStyle { $0.color = c.1 } }
                }
            } label: {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(session.textStyle.color)
                    .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(Theme.border, lineWidth: 1))
                    .frame(width: 18, height: 18)
                    .frame(width: 40, height: 40)
                    .background(Theme.card, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Theme.border, lineWidth: 1))
            }
            .accessibilityLabel("Renk")
        }
    }

    private var familyChoices: [String] {
        var list = TextStyle.families
        if !list.contains(session.textStyle.family) { list.insert(session.textStyle.family, at: 0) }
        return list
    }

    private var sizeChoices: [CGFloat] {
        var list = TextStyle.sizes
        if !list.contains(session.textStyle.size) { list.append(session.textStyle.size); list.sort() }
        return list
    }

    static func sizeText(_ v: CGFloat) -> String {
        v.rounded() == v ? "\(Int(v))" : String(format: "%.1f", v)
    }
}

/// B / I düğmesi (seçiliyken mavi kenarlık ve açık mavi zemin).
struct StyleToggle: View {
    let label: String
    let selected: Bool
    var bold = false
    var italic = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 16, weight: bold ? .bold : .regular))
                .italic(italic)
                .foregroundStyle(Theme.text)
                .frame(width: 40, height: 40)
                .background(selected ? Theme.chipSelected : Theme.card, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(selected ? Theme.blue : Theme.border, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

/// "İçerik ekle" ızgarasındaki kutucuk görünümü.
struct AddTileLabel: View {
    let title: String
    let icon: String
    let selected: Bool

    var body: some View {
        VStack(spacing: 5) {
            Image(systemName: icon).font(.system(size: 19))
            Text(title).font(.system(size: 11)).lineLimit(1).minimumScaleFactor(0.8)
        }
        .foregroundStyle(Theme.text)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .padding(.horizontal, 2)
        .background(selected ? Theme.chipSelected : Theme.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
            .strokeBorder(selected ? Theme.blue : Theme.border, lineWidth: 1))
        .contentShape(Rectangle())
    }
}

struct AddTile: View {
    let title: String
    let icon: String
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) { AddTileLabel(title: title, icon: icon, selected: selected) }
            .buttonStyle(.plain)
    }
}

/// 48x44 simge düğmesi.
struct SquareIconButton: View {
    let icon: String
    let label: String
    var selected = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 17))
                .foregroundStyle(Theme.text)
                .frame(width: 48, height: 44)
                .background(selected ? Theme.chipSelected : Theme.card, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(selected ? Theme.blue : Theme.border, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

// MARK: - Üstbilgi / altbilgi

struct HeaderFooterForm: View {
    @ObservedObject var session: DocumentSession
    @Environment(\.dismiss) private var dismiss
    @State private var header = ""
    @State private var footer = ""
    @State private var numbering = true
    @State private var numberFormat = "Sayfa {n} / {N}"
    @State private var position: PDFiumNumberPosition = .bottomCenter
    @State private var size: CGFloat = 10
    @State private var margin: CGFloat = 28

    var body: some View {
        PanelPage(title: "Üstbilgi ve altbilgi") {
            TextField("Üstbilgi (ör. Şirket adı)", text: $header).textFieldStyle(.roundedBorder)
            TextField("Altbilgi (ör. Gizlidir · {tarih})", text: $footer).textFieldStyle(.roundedBorder)
            Toggle("Sayfa numarası", isOn: $numbering)
            if numbering {
                TextField("Biçim", text: $numberFormat).textFieldStyle(.roundedBorder)
                Picker("Konum", selection: $position) {
                    ForEach(PDFiumNumberPosition.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
            }
            Stepper("Yazı boyutu: \(Int(size)) pt", value: $size, in: 6...24)
            Stepper("Kenar boşluğu: \(Int(margin)) pt", value: $margin, in: 10...72, step: 2)
            Text("{n} sayfa numarası, {N} toplam sayfa, {tarih} bugünün tarihi olur. Metin PDF'e gerçek metin olarak eklenir.")
                .font(.system(size: 12.5))
                .foregroundStyle(Theme.secondary)
            PrimaryButton(title: "Tüm sayfalara uygula") {
                session.applyHeaderFooter(header: header, footer: footer, numberFormat: numbering ? numberFormat : nil,
                                          position: position, size: size, color: .black, margin: margin)
                dismiss()
            }
        }
        .font(.system(size: 14.5))
    }
}

// MARK: - Filigran

struct WatermarkForm: View {
    @ObservedObject var session: DocumentSession
    @Environment(\.dismiss) private var dismiss
    @State private var text = "GİZLİ"
    @State private var size: CGFloat = 60
    @State private var opacity: CGFloat = 0.18
    @State private var angle: CGFloat = 45
    @State private var bold = true
    @State private var color: Color = Color(hex: 0xD0271F)

    var body: some View {
        PanelPage(title: "Filigran") {
            TextField("Filigran metni", text: $text).textFieldStyle(.roundedBorder)
            VStack(alignment: .leading) {
                Text("Boyut: \(Int(size)) pt")
                Slider(value: $size, in: 20...140)
            }
            VStack(alignment: .leading) {
                Text("Opaklık: %\(Int(opacity * 100))")
                Slider(value: $opacity, in: 0.05...0.8)
            }
            VStack(alignment: .leading) {
                Text("Açı: \(Int(angle))°")
                Slider(value: $angle, in: -90...90, step: 5)
            }
            Toggle("Kalın", isOn: $bold)
            ColorPicker("Renk", selection: $color, supportsOpacity: false)
            PrimaryButton(title: "Tüm sayfalara uygula") {
                session.applyWatermark(text: text, size: size, color: UIColor(color), opacity: opacity, angle: angle, bold: bold)
                dismiss()
            }
        }
        .font(.system(size: 14.5))
    }
}
