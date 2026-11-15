import SwiftUI

/// Dönüştür paneli: biçim seçimi, tanınan metin dili, mavi düğme (metni seçime göre değişir),
/// altta PDF'ye Dönüştür · Sıkıştır · Tara ve OCR.
struct ConvertPanel: View {
    let name: String
    let dataProvider: () -> Data?
    var preset: ConvertTarget?
    var onClose: (() -> Void)?
    var onCreatePDF: (() -> Void)?
    var onCompress: (() -> Void)?
    var onOCR: (() -> Void)?

    @StateObject private var job = ToolJob()
    @State private var options = ConvertOptions()
    @State private var language: OCRLanguage = .turkish
    @State private var didPreset = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Dönüştür")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(Theme.text)
                Spacer()
                if let onClose {
                    Button(action: onClose) {
                        Image(systemName: "xmark")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(Theme.secondary)
                            .frame(width: 44, height: 44, alignment: .trailing)
                    }
                    .accessibilityLabel("Kapat")
                }
            }
            .padding(.top, 4)

            SectionLabel(text: "PDF'yi dışa aktarma formatı")

            ForEach(ConvertTarget.allCases) { t in
                RadioRow(title: t.label, trailing: badge(for: t), selected: options.target == t) {
                    options.target = t
                    job.output = nil
                }
            }

            if options.target == .image {
                Picker("Görüntü biçimi", selection: $options.imageFormat) {
                    ForEach(ImageFormat.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
            } else if options.target == .other {
                Picker("Metin biçimi", selection: $options.otherFormat) {
                    ForEach(OtherTextFormat.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
            }

            HStack {
                Text("Tanınan metin dili")
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.tertiary)
                Spacer()
                Menu {
                    Picker("Tanınan metin dili", selection: $language) {
                        ForEach(OCRLanguage.allCases) { Text($0.title).tag($0) }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Text(language.title).font(.system(size: 14))
                        Image(systemName: "chevron.up.chevron.down").font(.system(size: 11))
                    }
                    .foregroundStyle(Theme.text)
                    .padding(.horizontal, 10)
                    .frame(height: 40)
                    .background(Theme.card, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Theme.border, lineWidth: 1))
                }
            }
            .padding(.top, 6)

            PrimaryButton(title: options.buttonTitle, busy: job.running) { convert() }
                .padding(.top, 6)

            if let e = job.error {
                Text(e).font(.system(size: 13)).foregroundStyle(Theme.accent)
            }
            if let out = job.output {
                ToolResultView(output: out, allowOpen: false)
            }

            if onCreatePDF != nil || onCompress != nil || onOCR != nil {
                HStack(spacing: 8) {
                    if let onCreatePDF { OutlineButton(title: "PDF'ye Dönüştür", action: onCreatePDF) }
                    if let onCompress { OutlineButton(title: "Sıkıştır", action: onCompress) }
                    if let onOCR { OutlineButton(title: "Tara ve OCR", action: onOCR) }
                }
                .padding(.top, 4)
            }
        }
        .onAppear {
            if !didPreset, let preset { options.target = preset; didPreset = true }
        }
    }

    private func badge(for t: ConvertTarget) -> String {
        switch t {
        case .image: return options.target == .image ? options.imageFormat.title : t.badge
        case .other: return options.target == .other ? options.otherFormat.title : t.badge
        default: return t.badge
        }
    }

    private func convert() {
        guard let data = dataProvider() else {
            job.error = "Belge hazırlanamadı."
            return
        }
        PDFOCRService.preferredLanguages = language.visionLanguages
        let o = options
        let base = (name as NSString).deletingPathExtension
        job.run {
            let folder = try DocTools.freshOutputFolder()
            let urls = try PDFConvertService.convert(data: data, baseName: base, folder: folder, options: o)
            guard !urls.isEmpty else { throw QPDFError.message("Çıktı üretilemedi.") }
            return ToolOutput(urls: urls, note: o.target == .word || o.target == .excel || o.target == .powerpoint
                              ? "Office dönüştürmeleri metni, temel biçimleri ve tabloları aktarır; sayfa düzeni birebir olmayabilir." : nil)
        }
    }
}
