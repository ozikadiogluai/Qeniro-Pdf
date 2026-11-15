import SwiftUI
import AppKit
import PDFKit

// MARK: - Ortak bileşenler

/// Sol panel başlığı: büyük başlık, isteğe bağlı geri düğmesi ve ✕.
struct ToolPanelHeader: View {
    let title: String
    var onBack: (() -> Void)? = nil
    let onClose: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            if let onBack {
                Button(action: onBack) {
                    Image(systemName: "chevron.left").font(.system(size: 14, weight: .semibold))
                }
                .buttonStyle(.plain)
                .help("Geri")
            }
            Text(title).font(.system(size: 20, weight: .bold))
            Spacer()
            Button(action: onClose) {
                Image(systemName: "xmark").font(.system(size: 13, weight: .semibold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Paneli kapat")
        }
        .padding(.bottom, 10)
    }
}

/// Küçük, büyük harfli bölüm başlığı ("SAYFAYI DEĞİŞTİR").
struct PanelCapsTitle: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .kerning(0.8)
            .foregroundStyle(.secondary)
            .padding(.top, 14)
            .padding(.bottom, 4)
            .padding(.horizontal, 8)
    }
}

/// Araç listesi satırı: renkli simge + başlık.
struct ToolListRow: View {
    let symbol: String
    let title: String
    var iconColor: Color? = nil
    var active: Bool = false
    var trailing: String? = nil
    var bold: Bool = false
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: symbol)
                    .font(.system(size: 16))
                    .frame(width: 24)
                    .foregroundStyle(iconColor ?? (active ? Theme.selection : Color.primary))
                Text(title)
                    .font(.system(size: 14, weight: bold ? .semibold : .regular))
                    .foregroundStyle(Color.primary)
                Spacer(minLength: 4)
                if let trailing {
                    Text(trailing).font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 8)
            .background(RoundedRectangle(cornerRadius: 8).fill(active ? Theme.activeNav : (hover ? Theme.activeNav.opacity(0.5) : Color.clear)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }
}

/// Kare simge düğmesi (Sayfayı değiştir satırı).
struct SquareIconButton: View {
    let symbol: String
    let help: String
    var active: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 16))
                .frame(width: 42, height: 40)
                .foregroundStyle(active ? Theme.selection : Color.primary)
                .background(RoundedRectangle(cornerRadius: 8).fill(active ? Theme.activeNav : Theme.window))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(active ? Theme.selection : Theme.border, lineWidth: 1))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
    }
}

// MARK: - Tüm araçlar

struct AllToolsPanel: View {
    @EnvironmentObject var app: AppState
    @ObservedObject var session: DocumentSession
    @State private var showMore = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 2) {
                ToolPanelHeader(title: "Tüm araçlar", onClose: { session.panel = nil })
                row("arrow.up.doc", "PDF olarak dışa aktar", 0x0E8A7E) { session.viewerTab = .convert }
                row("square.and.pencil", "PDF Düzenle", 0xD2338A) { app.perform(.edit) }
                row("signature", "E-imza iste", 0xB03AC4) {
                    session.viewerTab = .sign
                    session.panel = .tab
                    session.tool = .addSignatureField
                }
                row("pencil.and.outline", "Doldur ve İmzala", 0x7C4DDB) { app.perform(.signFill) }
                row("doc.badge.plus", "PDF oluştur", 0xE5322D) { app.perform(.create) }
                row("square.on.square", "Dosyaları birleştir", 0x2D6BE4) { app.perform(.merge) }
                row("square.grid.2x2", "Sayfaları organize et", 0x5BA632) { app.perform(.organize) }
                row("square.and.arrow.up", "Yorum için gönder", 0xC99A06) { session.shareForReview() }
                row("doc.text.viewfinder", "Tarama ve OCR", 0x1E8E3E) { session.runOCR(force: false) }
                row("lock.shield", "PDF koru", 0x4F5BD5) { app.perform(.protect) }
                row("eye.slash", "PDF'yi redakte et", 0xD2338A) { app.perform(.redact) }
                row("arrow.down.right.and.arrow.up.left", "PDF sıkıştır", 0xE5322D) { app.perform(.compress) }
                row("list.bullet.rectangle", "Form hazırla", 0x7C4DDB) { session.panel = .formPrepare }
                row("text.bubble", "Yorum ekleyin", 0xC99A06) { session.tool = .note }
                if showMore {
                    row("scissors", "PDF böl", 0xE5322D) { app.perform(.split) }
                    row("doc.richtext", "PDF'yi Word'e", 0x2D6BE4) { app.perform(.toWord) }
                    row("tablecells", "PDF'yi Excel'e", 0x1E8E3E) { app.perform(.toExcel) }
                    row("rectangle.on.rectangle.angled", "PDF'yi PowerPoint'e", 0xE8710A) { app.perform(.toPowerPoint) }
                    row("checkmark.seal", "Sertifika ile İmzala", 0x7C4DDB) { app.perform(.certificateSign) }
                    row("checkmark.shield", "İmzaları doğrula", 0x4F5BD5) {
                        session.viewerTab = .sign
                        session.panel = .verifySignatures
                    }
                    row("trash.slash", "Hassas bilgileri kaldır", 0xE5322D) { app.perform(.sanitize) }
                    row("menubar.rectangle", "Üstbilgi ve altbilgi", 0xD2338A) {
                        session.viewerTab = .edit
                        session.panel = .headerFooter
                    }
                    row("drop", "Filigran", 0xD2338A) {
                        session.viewerTab = .edit
                        session.panel = .watermark
                    }
                }
                Button(showMore ? "Daha az göster" : "Daha fazla göster") {
                    withAnimation(.easeInOut(duration: 0.15)) { showMore.toggle() }
                }
                .buttonStyle(.link)
                .font(.system(size: 14))
                .padding(.horizontal, 8)
                .padding(.top, 10)
            }
            .padding(16)
        }
    }

    private func row(_ symbol: String, _ title: String, _ color: UInt32, action: @escaping () -> Void) -> some View {
        ToolListRow(symbol: symbol, title: title, iconColor: Color(nsColor: Theme.hex(color)), action: action)
    }
}

// MARK: - Dönüştür

struct ConvertTabPanel: View {
    @EnvironmentObject var app: AppState
    @ObservedObject var session: DocumentSession

    enum Format: String, CaseIterable, Identifiable {
        case word, powerpoint, excel, image, other
        var id: String { rawValue }
        var title: String {
            switch self {
            case .word: return "Microsoft Word"
            case .powerpoint: return "Microsoft PowerPoint"
            case .excel: return "Microsoft Excel"
            case .image: return "Görüntü formatı"
            case .other: return "Diğer format"
            }
        }
    }

    static let languages: [(code: String, name: String)] = [
        ("tr-TR", "Türkçe"), ("en-US", "İngilizce"), ("de-DE", "Almanca"), ("fr-FR", "Fransızca"),
        ("es-ES", "İspanyolca"), ("it-IT", "İtalyanca"), ("pt-BR", "Portekizce")
    ]

    @State private var format: Format = .word
    @State private var imageFormat: ImageFormat = .jpeg
    @State private var otherTarget: ConvertTarget = .rtf
    @State private var language = "tr-TR"
    @State private var running = false

    private func extLabel(_ f: Format) -> String {
        switch f {
        case .word: return "DOCX"
        case .powerpoint: return "PPTX"
        case .excel: return "XLSX"
        case .image: return imageFormat.title
        case .other:
            switch otherTarget {
            case .text: return "TXT"
            case .html: return "HTML"
            default: return "RTF"
            }
        }
    }

    private var buttonTitle: String {
        let ext = extLabel(format)
        // Türkçe ünlü uyumu: "DOCX'e", "RTF'ye".
        let yeSuffix: Set<String> = ["PNG", "RTF", "TXT", "HTML"]
        return ext + (yeSuffix.contains(ext) ? "'ye" : "'e") + " Dönüştür"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                ToolPanelHeader(title: "Dönüştür", onClose: { session.panel = nil })
                PanelCapsTitle("PDF'Yİ DIŞA AKTARMA FORMATI")
                formatRow(.word) { Text("DOCX").formatTag() }
                formatRow(.powerpoint) { Text("PPTX").formatTag() }
                formatRow(.excel) { Text("XLSX").formatTag() }
                formatRow(.image) {
                    Picker("", selection: $imageFormat) {
                        ForEach(ImageFormat.allCases) { Text($0.title).tag($0) }
                    }
                    .labelsHidden()
                    .fixedSize()
                }
                formatRow(.other) {
                    Picker("", selection: $otherTarget) {
                        Text("RTF").tag(ConvertTarget.rtf)
                        Text("TXT").tag(ConvertTarget.text)
                        Text("HTML").tag(ConvertTarget.html)
                    }
                    .labelsHidden()
                    .fixedSize()
                }

                Text("Tanınan metin dili")
                    .font(.system(size: 13, weight: .semibold))
                    .padding(.top, 10)
                    .padding(.horizontal, 4)
                Picker("", selection: $language) {
                    ForEach(Self.languages, id: \.code) { Text($0.name).tag($0.code) }
                }
                .labelsHidden()
                .padding(.horizontal, 4)
                Text("Taranmış sayfalarda metin bu dile göre tanınır (OCR).")
                    .font(.caption).foregroundStyle(.secondary)
                    .padding(.horizontal, 4)

                HStack {
                    Spacer()
                    Button(action: run) {
                        Text(buttonTitle)
                            .font(.system(size: 14, weight: .semibold))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                    }
                    .buttonStyle(.borderedProminent)
                    .buttonBorderShape(.capsule)
                    .tint(Theme.selection)
                    .controlSize(.large)
                    .disabled(running)
                }
                .padding(.top, 8)

                PanelCapsTitle("DİĞER SEÇENEKLER")
                ToolListRow(symbol: "doc.badge.plus", title: "PDF'ye Dönüştür") { app.perform(.create) }
                ToolListRow(symbol: "arrow.down.right.and.arrow.up.left", title: "PDF sıkıştır") { app.perform(.compress) }
                ToolListRow(symbol: "doc.text.viewfinder", title: "Tara ve OCR Uygula") {
                    applyLanguage()
                    session.runOCR(force: false)
                }
            }
            .padding(16)
        }
    }

    private func formatRow<Trailing: View>(_ f: Format, @ViewBuilder trailing: () -> Trailing) -> some View {
        let selected = format == f
        return HStack(spacing: 10) {
            Image(systemName: selected ? "largecircle.fill.circle" : "circle")
                .font(.system(size: 15))
                .foregroundStyle(selected ? Theme.selection : Color.secondary)
            Text(f.title).font(.system(size: 14))
            Spacer(minLength: 4)
            trailing()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 8).fill(selected ? Theme.activeNav.opacity(0.5) : Color.clear))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(selected ? Theme.selection : Theme.border, lineWidth: 1))
        .contentShape(Rectangle())
        .onTapGesture { format = f }
    }

    private func applyLanguage() {
        PDFOCRService.preferredLanguages = language == "en-US" ? ["en-US"] : [language, "en-US"]
    }

    private func run() {
        guard let data = session.currentData() else {
            Dialogs.info("Belge hazırlanamadı")
            return
        }
        guard let folder = Dialogs.chooseFolder(title: "Dönüştürülen dosyanın kaydedileceği klasörü seçin") else { return }
        var o = ConvertOptions()
        switch format {
        case .word: o.target = .word
        case .powerpoint: o.target = .powerpoint
        case .excel: o.target = .excel
        case .image:
            o.target = .image
            o.imageFormat = imageFormat
            o.dpi = 150
        case .other: o.target = otherTarget
        }
        o.useOCR = true
        applyLanguage()
        let base = session.url?.baseName ?? session.displayName.replacingOccurrences(of: ".pdf", with: "")
        let input = folder.appendingPathComponent(base + ".pdf")
        let opts = o
        let label = extLabel(format)
        running = true
        session.busyMessage = "\(label) biçimine dönüştürülüyor…"
        Task { @MainActor in
            do {
                let urls = try await Task.detached(priority: .userInitiated) {
                    try PDFConvertService.convert(input: input, data: data, folder: folder, options: opts)
                }.value
                session.busyMessage = nil
                running = false
                app.notice("Dönüştür (\(label)): \(urls.count) dosya oluşturuldu.", urls: urls)
                Dialogs.revealInFinder(urls)
            } catch {
                session.busyMessage = nil
                running = false
                Dialogs.error("Dönüştürülemedi", error)
            }
        }
    }
}

private extension Text {
    func formatTag() -> some View {
        self.font(.system(size: 12, weight: .semibold))
            .kerning(0.4)
            .foregroundStyle(.secondary)
    }
}

// MARK: - Üstbilgi ve altbilgi

struct HeaderFooterPanel: View {
    @ObservedObject var session: DocumentSession
    @State private var header = ""
    @State private var footer = ""
    @State private var addNumbers = true
    @State private var numberFormat = "Sayfa {n} / {N}"
    @State private var position: PDFiumEditor.NumberPosition = .bottomRight
    @State private var size: Double = 10
    @State private var color: Color = .black
    @State private var margin: Double = 24

    static let formats: [(String, String)] = [
        ("Sayfa {n} / {N}", "Sayfa 1 / 5"), ("{n} / {N}", "1 / 5"), ("{n}", "1"), ("- {n} -", "- 1 -")
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                ToolPanelHeader(title: "Üstbilgi ve altbilgi",
                                onBack: { session.panel = .tab },
                                onClose: { session.panel = nil })
                Text("Metin tüm sayfalara gerçek PDF metni olarak eklenir. {n} sayfa numarası, {N} toplam sayfa, {tarih} bugünün tarihi olur.")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Üstbilgi (ortada)").font(.callout.weight(.semibold))
                TextField("ör. Qeniro — Gizli", text: $header).textFieldStyle(.roundedBorder)
                Text("Altbilgi (ortada)").font(.callout.weight(.semibold))
                TextField("ör. {tarih}", text: $footer).textFieldStyle(.roundedBorder)
                Toggle("Sayfa numarası ekle", isOn: $addNumbers)
                if addNumbers {
                    Picker("Biçim", selection: $numberFormat) {
                        ForEach(Self.formats, id: \.0) { Text($0.1).tag($0.0) }
                    }
                    Picker("Konum", selection: $position) {
                        ForEach(PDFiumEditor.NumberPosition.allCases) { Text($0.rawValue).tag($0) }
                    }
                }
                HStack {
                    Text("Boyut")
                    Slider(value: $size, in: 6...24, step: 1)
                    Text("\(Int(size)) pt").monospacedDigit().frame(width: 40)
                }
                HStack {
                    Text("Kenar boşluğu")
                    Slider(value: $margin, in: 8...72, step: 2)
                    Text("\(Int(margin))").monospacedDigit().frame(width: 30)
                }
                ColorPicker("Renk", selection: $color, supportsOpacity: false)
                Button {
                    session.applyHeaderFooter(header: header, footer: footer,
                                              numberFormat: addNumbers ? numberFormat : nil,
                                              position: position, size: CGFloat(size),
                                              color: NSColor(color), margin: CGFloat(margin))
                } label: {
                    Text("Tüm sayfalara uygula").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.selection)
                .controlSize(.large)
                .disabled(header.trimmingCharacters(in: .whitespaces).isEmpty
                          && footer.trimmingCharacters(in: .whitespaces).isEmpty && !addNumbers)
                Text("Geri almak için ⌘Z kullanın. Kaydetmeyi unutmayın.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .padding(16)
        }
    }
}

// MARK: - Filigran

struct WatermarkPanel: View {
    @ObservedObject var session: DocumentSession
    @State private var text = "GİZLİ"
    @State private var size: Double = 72
    @State private var opacity: Double = 0.25
    @State private var angle: Double = 45
    @State private var color: Color = Color(nsColor: Theme.hex(0x9AA1AB))
    @State private var bold = true

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                ToolPanelHeader(title: "Filigran",
                                onBack: { session.panel = .tab },
                                onClose: { session.panel = nil })
                Text("Metin")
                    .font(.callout.weight(.semibold))
                TextField("ör. GİZLİ, TASLAK", text: $text).textFieldStyle(.roundedBorder)
                HStack {
                    Text("Boyut")
                    Slider(value: $size, in: 18...160, step: 2)
                    Text("\(Int(size))").monospacedDigit().frame(width: 34)
                }
                HStack {
                    Text("Opaklık")
                    Slider(value: $opacity, in: 0.05...1)
                    Text("%\(Int(opacity * 100))").monospacedDigit().frame(width: 40)
                }
                HStack {
                    Text("Açı")
                    Slider(value: $angle, in: -90...90, step: 5)
                    Text("\(Int(angle))°").monospacedDigit().frame(width: 40)
                }
                HStack {
                    ColorPicker("Renk", selection: $color, supportsOpacity: false)
                    Spacer()
                    Toggle("Kalın", isOn: $bold)
                }
                // Önizleme
                ZStack {
                    RoundedRectangle(cornerRadius: 6).fill(Color.white)
                    Text(text.isEmpty ? " " : text)
                        .font(.system(size: max(8, size / 6), weight: bold ? .bold : .regular))
                        .foregroundStyle(color.opacity(opacity))
                        .rotationEffect(.degrees(-angle))
                }
                .frame(height: 120)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Theme.border))
                Button {
                    session.applyWatermark(text: text, size: CGFloat(size), color: NSColor(color),
                                           opacity: CGFloat(opacity), angle: CGFloat(angle), bold: bold)
                } label: {
                    Text("Tüm sayfalara uygula").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.selection)
                .controlSize(.large)
                .disabled(text.trimmingCharacters(in: .whitespaces).isEmpty)
                Text("Filigran sayfa içeriğine gerçek metin olarak eklenir. Geri almak için ⌘Z.")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(16)
        }
    }
}

// MARK: - Form hazırla

struct FormPreparePanel: View {
    @ObservedObject var session: DocumentSession

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 2) {
                ToolPanelHeader(title: "Form hazırla",
                                onBack: { session.panel = .tab; session.tool = .select },
                                onClose: { session.panel = nil; session.tool = .select })
                Text("Alan türünü seçin, sonra sayfada bir yere tıklayın. Alanlar doldurulabilir form alanı olarak kaydedilir.")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, 8)
                ToolListRow(symbol: "character.textbox", title: "Metin alanı", active: session.tool == .addTextField) { session.tool = .addTextField }
                ToolListRow(symbol: "checkmark.square", title: "Onay kutusu", active: session.tool == .addCheckbox) { session.tool = .addCheckbox }
                ToolListRow(symbol: "smallcircle.filled.circle", title: "Radyo düğmesi", active: session.tool == .addRadio) { session.tool = .addRadio }
                ToolListRow(symbol: "chevron.down.square", title: "Açılır liste", active: session.tool == .addDropdown) { session.tool = .addDropdown }
                ToolListRow(symbol: "signature", title: "İmza alanı", active: session.tool == .addSignatureField) { session.tool = .addSignatureField }
                if session.selectedAnnotation != nil {
                    Divider().padding(.vertical, 8)
                    Button(role: .destructive) { session.deleteSelected() } label: {
                        Label("Seçili alanı sil", systemImage: "trash")
                    }
                }
            }
            .padding(16)
        }
    }
}
