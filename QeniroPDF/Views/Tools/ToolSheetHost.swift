import SwiftUI
import AppKit
import PDFKit
import UniformTypeIdentifiers

/// Araç penceresini türüne göre seçer.
struct ToolSheetHost: View {
    @EnvironmentObject var app: AppState
    let request: ToolSheetRequest

    @State private var inputs: [URL] = []
    @State private var ready = false

    var body: some View {
        if !ready {
            ProgressView()
                .padding(40)
                .onAppear {
                    inputs = ToolIO.resolveInputs(request, app: app)
                    ready = true
                }
        } else {
            content
        }
    }

    @ViewBuilder
    private var content: some View {
        switch request.kind {
        case .create: CreateToolView(initialFiles: request.files)
        case .merge: MergeToolView(files: inputs)
        case .split: SplitToolView(files: Array(inputs.prefix(1)))
        case .compress: CompressToolView(files: inputs)
        case .protect: ProtectToolView(files: Array(inputs.prefix(1)))
        case .convert: ConvertToolView(kind: .convert, target: .word, files: inputs)
        case .toWord: ConvertToolView(kind: .toWord, target: .word, files: inputs)
        case .toExcel: ConvertToolView(kind: .toExcel, target: .excel, files: inputs)
        case .toPowerPoint: ConvertToolView(kind: .toPowerPoint, target: .powerpoint, files: inputs)
        case .sanitize: SanitizeToolView(files: inputs)
        case .certificateSign: CertificateSignView(sessionID: request.sessionID)
        default:
            VStack(spacing: 12) {
                Text(request.kind.title).font(.title3.bold())
                Text("Bu araç açık bir belge üzerinde çalışır.")
                Button("Kapat") { app.sheet = nil }
            }
            .padding(30)
        }
    }
}

// MARK: - Birleştir

struct MergeToolView: View {
    @EnvironmentObject var app: AppState
    @State var files: [URL]
    @State private var state: ToolRunState = .idle

    var body: some View {
        ToolScaffold(kind: .merge, runTitle: "Birleştir", canRun: files.count >= 2, state: state, run: run) {
            FileListEditor(files: $files, types: [.pdf], multiple: true, reorderable: true, title: "Birleştirilecek PDF'ler (yukarıdan aşağıya sırayla)")
            if files.count == 1 {
                Text("En az iki PDF ekleyin.").font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func run() {
        guard let out = Dialogs.save(suggestedName: "Birlesik.pdf", type: .pdf, title: "Birleştirilmiş PDF'yi kaydet",
                                     directory: ToolIO.directory(for: files.first)) else { return }
        let inputs = files
        state = .running("Birleştiriliyor…")
        Task { @MainActor in
            do {
                let pages = try await Task.detached(priority: .userInitiated) { try PDFMergeService.merge(inputs, to: out) }.value
                state = .done("\(inputs.count) dosya birleştirildi (\(pages) sayfa).", [out])
                app.notice("PDF Birleştir: \(out.lastPathComponent) oluşturuldu.", urls: [out])
            } catch {
                state = .failed(error.localizedDescription)
            }
        }
    }
}

// MARK: - Böl

struct SplitToolView: View {
    @EnvironmentObject var app: AppState
    @State var files: [URL]
    @State private var mode = 0
    @State private var ranges = "1-3, 4-"
    @State private var everyN = 1
    @State private var state: ToolRunState = .idle

    private var pageCount: Int {
        guard let u = files.first, let d = PDFDocument(url: u) else { return 0 }
        return d.pageCount
    }

    var body: some View {
        ToolScaffold(kind: .split, runTitle: "Böl", canRun: !files.isEmpty, state: state, run: run) {
            FileListEditor(files: $files, types: [.pdf], multiple: false, title: "Bölünecek PDF")
            if !files.isEmpty { Text("Toplam \(pageCount) sayfa").font(.caption).foregroundStyle(.secondary) }
            Picker("Bölme şekli", selection: $mode) {
                Text("Sayfa aralıkları").tag(0)
                Text("Her N sayfada bir").tag(1)
                Text("Her sayfa ayrı dosya").tag(2)
            }
            .pickerStyle(.radioGroup)
            if mode == 0 {
                TextField("Örnek: 1-3, 5, 8-", text: $ranges)
                    .textFieldStyle(.roundedBorder)
                Text("Her aralık ayrı bir PDF olur. \"8-\" sekizinci sayfadan sona kadar demektir.")
                    .font(.caption).foregroundStyle(.secondary)
            } else if mode == 1 {
                Stepper("Her \(everyN) sayfada bir dosya", value: $everyN, in: 1...999)
            }
        }
    }

    private func run() {
        guard let input = files.first, let folder = Dialogs.chooseFolder(title: "Parçaların kaydedileceği klasörü seçin") else { return }
        let splitMode: SplitMode = mode == 0 ? .ranges(ranges) : (mode == 1 ? .everyN(everyN) : .single)
        state = .running("Bölünüyor…")
        Task { @MainActor in
            do {
                let urls = try await Task.detached(priority: .userInitiated) {
                    try PDFSplitService.split(input: input, data: nil, mode: splitMode, folder: folder, baseName: input.baseName)
                }.value
                state = .done("\(urls.count) dosya oluşturuldu.", urls)
                app.notice("PDF Böl: \(input.lastPathComponent) → \(urls.count) dosya.", urls: urls)
            } catch {
                state = .failed(error.localizedDescription)
            }
        }
    }
}

// MARK: - Sıkıştır

struct CompressToolView: View {
    @EnvironmentObject var app: AppState
    @State var files: [URL]
    @State private var level: CompressionLevel = .medium
    @State private var rasterize = false
    @State private var state: ToolRunState = .idle

    var body: some View {
        ToolScaffold(kind: .compress, runTitle: "Sıkıştır", canRun: !files.isEmpty, state: state, run: run) {
            FileListEditor(files: $files, types: [.pdf], multiple: true, title: "Sıkıştırılacak PDF'ler")
            Picker("Sıkıştırma düzeyi", selection: $level) {
                ForEach(CompressionLevel.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.radioGroup)
            Toggle("Sayfaları görüntüye çevir (en yüksek sıkıştırma; metin OCR ile korunur)", isOn: $rasterize)
            Text("Çıktılar özgün dosyaların yanına \"_sıkıştırılmış\" ekiyle kaydedilir.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private func run() {
        let inputs = files
        var folder: URL?
        if inputs.contains(where: { ToolIO.isTemporary($0) }) {
            guard let f = Dialogs.chooseFolder() else { return }
            folder = f
        }
        let lvl = level, raster = rasterize
        let outFolder = folder
        state = .running("Sıkıştırılıyor…")
        Task { @MainActor in
            var lines: [String] = []
            var outs: [URL] = []
            for input in inputs {
                let out: URL
                if let outFolder { out = outFolder.appendingPathComponent(input.baseName + "_sıkıştırılmış.pdf") }
                else { out = input.uniqueSibling(suffix: "_sıkıştırılmış", ext: "pdf") }
                state = .running("Sıkıştırılıyor: \(input.lastPathComponent)")
                do {
                    let r = try await Task.detached(priority: .userInitiated) {
                        try PDFCompressService.compress(input: input, data: nil, output: out, level: lvl, rasterize: raster)
                    }.value
                    var line = "\(input.lastPathComponent): \(ToolIO.sizeChange(r.before, r.after))"
                    if let note = r.note { line += "\n  \(note)" }
                    lines.append(line)
                    outs.append(out)
                } catch {
                    lines.append("\(input.lastPathComponent): \(error.localizedDescription)")
                }
            }
            state = outs.isEmpty ? .failed(lines.joined(separator: "\n")) : .done(lines.joined(separator: "\n"), outs)
            if !outs.isEmpty { app.notice("PDF Sıkıştır: \(outs.count) dosya tamamlandı.", urls: outs) }
        }
    }
}

// MARK: - Koruma

struct ProtectToolView: View {
    @EnvironmentObject var app: AppState
    @State var files: [URL]
    @State private var mode = 0
    @State private var openPassword = ""
    @State private var confirm = ""
    @State private var permPassword = ""
    @State private var allowPrinting = true
    @State private var allowCopying = false
    @State private var currentPassword = ""
    @State private var state: ToolRunState = .idle

    private var canRun: Bool {
        guard !files.isEmpty else { return false }
        if mode == 1 { return true }
        if openPassword.isEmpty && permPassword.isEmpty { return false }
        return openPassword == confirm
    }

    var body: some View {
        ToolScaffold(kind: .protect, runTitle: mode == 0 ? "Koru" : "Şifreyi Kaldır", canRun: canRun, state: state, run: run) {
            FileListEditor(files: $files, types: [.pdf], multiple: false, title: "PDF")
            Picker("", selection: $mode) {
                Text("Şifre ekle").tag(0)
                Text("Şifreyi kaldır").tag(1)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            if mode == 0 {
                Form {
                    SecureField("Açma şifresi", text: $openPassword)
                    SecureField("Açma şifresi (tekrar)", text: $confirm)
                    if !openPassword.isEmpty && openPassword != confirm {
                        Text("Şifreler eşleşmiyor.").font(.caption).foregroundStyle(.red)
                    }
                    SecureField("İzin şifresi (isteğe bağlı)", text: $permPassword)
                    Toggle("Yazdırmaya izin ver", isOn: $allowPrinting)
                    Toggle("Metin ve görsel kopyalamaya izin ver", isOn: $allowCopying)
                }
                Text("Açma şifresi belgeyi açmak için gerekir. İzin şifresi yazdırma/kopyalama kısıtlarını değiştirmeyi korur. Şifreleme: 128 bit.")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                SecureField("Mevcut şifre", text: $currentPassword)
                    .textFieldStyle(.roundedBorder)
                Text("Belge şifresiz bir kopya olarak kaydedilir.").font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func run() {
        guard let input = files.first else { return }
        let suffix = mode == 0 ? "_korumalı" : "_şifresiz"
        guard let out = Dialogs.save(suggestedName: input.baseName + suffix + ".pdf", type: .pdf, title: "Kaydet",
                                     directory: ToolIO.directory(for: input)) else { return }
        let opts = ProtectOptions(openPassword: openPassword, permissionsPassword: permPassword,
                                  allowPrinting: allowPrinting, allowCopying: allowCopying)
        let m = mode, pw = currentPassword
        state = .running(m == 0 ? "Şifreleniyor…" : "Şifre kaldırılıyor…")
        Task { @MainActor in
            do {
                try await Task.detached(priority: .userInitiated) {
                    if m == 0 {
                        try PDFProtectService.protect(input: input, data: nil, output: out, options: opts)
                    } else {
                        try PDFProtectService.removePassword(input: input, password: pw, output: out)
                    }
                }.value
                state = .done(m == 0 ? "Belge şifre ile korundu." : "Şifre kaldırıldı.", [out])
                app.notice("Koruma: \(out.lastPathComponent) kaydedildi.", urls: [out])
            } catch {
                state = .failed(error.localizedDescription)
            }
        }
    }
}

// MARK: - Dönüştür (Word / Excel / PowerPoint / görsel / metin / OCR)

struct ConvertToolView: View {
    @EnvironmentObject var app: AppState
    let kind: ToolKind
    @State var target: ConvertTarget
    @State var files: [URL]
    @State private var imageFormat: ImageFormat = .png
    @State private var dpi: Double = 150
    @State private var useOCR = true
    @State private var preserveLayout = false
    @State private var useLibreOffice = false
    @State private var state: ToolRunState = .idle

    init(kind: ToolKind, target: ConvertTarget, files: [URL]) {
        self.kind = kind
        _target = State(initialValue: target)
        _files = State(initialValue: files)
        _preserveLayout = State(initialValue: target == .powerpoint)
    }

    var body: some View {
        ToolScaffold(kind: kind, runTitle: "Dönüştür", canRun: !files.isEmpty, state: state, run: run) {
            FileListEditor(files: $files, types: [.pdf], multiple: true, title: "PDF'ler (toplu dönüştürme desteklenir)")
            Picker("Hedef biçim", selection: $target) {
                ForEach(ConvertTarget.allCases) { Text($0.title).tag($0) }
            }
            .onChange(of: target) { _, t in preserveLayout = (t == .powerpoint) }
            switch target {
            case .image:
                HStack {
                    Picker("Biçim", selection: $imageFormat) {
                        ForEach(ImageFormat.allCases) { Text($0.title).tag($0) }
                    }
                    .frame(width: 180)
                    Picker("Çözünürlük", selection: $dpi) {
                        Text("72 dpi (ekran)").tag(72.0)
                        Text("150 dpi").tag(150.0)
                        Text("300 dpi (baskı)").tag(300.0)
                    }
                    .frame(width: 220)
                }
            case .word:
                Toggle("Görünümü koru (her sayfa görsel olarak eklenir, metin düzenlenemez)", isOn: $preserveLayout)
                Toggle("Taranmış sayfalarda metin tanıma (OCR)", isOn: $useOCR)
                if LibreOfficeBridge.isAvailable {
                    Toggle("LibreOffice ile dönüştür (daha yüksek düzen sadakati)", isOn: $useLibreOffice)
                }
            case .excel:
                Toggle("Taranmış sayfalarda metin tanıma (OCR)", isOn: $useOCR)
                Text("Her PDF sayfası ayrı bir çalışma sayfasına aktarılır; sütunlar metin konumlarından çıkarılır, sayılar sayı olarak yazılır.")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            case .powerpoint:
                Toggle("Görünümü koru (her sayfa bir slayt görseli)", isOn: $preserveLayout)
                if !preserveLayout {
                    Toggle("Taranmış sayfalarda metin tanıma (OCR)", isOn: $useOCR)
                }
            case .text:
                Toggle("Taranmış sayfalarda metin tanıma (OCR)", isOn: $useOCR)
            case .rtf, .html:
                EmptyView()
            case .searchable:
                Text("Yalnızca seçilebilir metni olmayan (taranmış) sayfalar işlenir. Türkçe ve İngilizce tanınır.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Text("Office dönüştürmeleri metni, temel biçimi, tabloları ve görselleri aktarır; karmaşık sayfa düzenleri birebir korunmayabilir.")
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func run() {
        guard let folder = Dialogs.chooseFolder(title: "Çıktıların kaydedileceği klasörü seçin") else { return }
        let inputs = files
        let opts = ConvertOptions(target: target, imageFormat: imageFormat, dpi: CGFloat(dpi), useOCR: useOCR,
                                  preserveLayout: preserveLayout, useLibreOffice: useLibreOffice)
        state = .running("Dönüştürülüyor…")
        Task { @MainActor in
            var outs: [URL] = []
            var errors: [String] = []
            for input in inputs {
                state = .running("Dönüştürülüyor: \(input.lastPathComponent)")
                do {
                    let urls = try await Task.detached(priority: .userInitiated) {
                        try PDFConvertService.convert(input: input, data: nil, folder: folder, options: opts)
                    }.value
                    outs.append(contentsOf: urls)
                } catch {
                    errors.append("\(input.lastPathComponent): \(error.localizedDescription)")
                }
            }
            if outs.isEmpty {
                state = .failed(errors.joined(separator: "\n"))
            } else {
                var msg = "\(outs.count) dosya oluşturuldu (\(opts.target.title))."
                if !errors.isEmpty { msg += "\nHatalar:\n" + errors.joined(separator: "\n") }
                state = .done(msg, outs)
                app.notice("PDF Dönüştür: \(outs.count) dosya oluşturuldu.", urls: outs)
            }
        }
    }
}

// MARK: - PDF Oluştur

struct CreateToolView: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss
    @State var files: [URL]
    @State private var source = 0
    @State private var fitToA4 = true
    @State private var blankCount = 1
    @State private var blankSize = 0
    @State private var text = ""
    @State private var state: ToolRunState = .idle

    init(initialFiles: [URL]) {
        _files = State(initialValue: initialFiles)
    }

    private var canRun: Bool {
        switch source {
        case 0: return !files.isEmpty
        case 2: return !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        default: return true
        }
    }

    var body: some View {
        ToolScaffold(kind: .create, runTitle: "Oluştur", canRun: canRun, state: state, run: run) {
            Picker("", selection: $source) {
                Text("Dosyalardan").tag(0)
                Text("Boş sayfa").tag(1)
                Text("Metinden").tag(2)
                Text("Panodan").tag(3)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            switch source {
            case 0:
                FileListEditor(files: $files, types: [UTType.image, .pdf, .text, .rtf, .html] + UTType.officeInputs, multiple: true, reorderable: true,
                               title: "Görseller, Word/Metin dosyaları, PDF'ler")
                Toggle("Görselleri A4 sayfaya sığdır", isOn: $fitToA4)
                Text(LibreOfficeBridge.isAvailable
                     ? "LibreOffice bulundu: Word, Excel ve PowerPoint dosyaları yüksek sadakatle dönüştürülür."
                     : "Word (.docx/.doc/.rtf/.odt) ve metin dosyaları yerleşik motorla dönüştürülür. Excel, PowerPoint, Pages, Numbers, Keynote için ücretsiz LibreOffice'i kurun.")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            case 1:
                Stepper("Sayfa sayısı: \(blankCount)", value: $blankCount, in: 1...500)
                Picker("Boyut", selection: $blankSize) {
                    Text("A4 dikey").tag(0)
                    Text("A4 yatay").tag(1)
                    Text("Letter").tag(2)
                }
                .frame(width: 240)
            case 2:
                TextEditor(text: $text)
                    .font(.system(size: 13))
                    .frame(height: 180)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Theme.border))
            default:
                Text("Panodaki PDF, görsel veya metin yeni bir PDF'e dönüştürülür. Önce bir şey kopyalayın (⌘C).")
                    .foregroundStyle(.secondary)
            }
            Text("Oluşturulan PDF yeni bir sekmede açılır; ardından ⌘S ile kaydedebilirsiniz.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private func run() {
        state = .running("Oluşturuluyor…")
        Task { @MainActor in
            do {
                let doc: PDFDocument
                let name: String
                switch source {
                case 0:
                    doc = try PDFCreateService.create(from: files, fitToA4: fitToA4)
                    name = files.count == 1 ? files[0].baseName : "Yeni Belge"
                case 1:
                    let size: CGSize = blankSize == 0 ? PageRenderer.a4 : (blankSize == 1 ? CGSize(width: PageRenderer.a4.height, height: PageRenderer.a4.width) : PageRenderer.letter)
                    doc = PDFCreateService.blank(count: blankCount, size: size)
                    name = "Boş Belge"
                case 2:
                    doc = try PDFCreateService.fromText(text)
                    name = "Metin Belgesi"
                default:
                    doc = try PDFCreateService.fromClipboard()
                    name = "Panodan"
                }
                app.openUnsaved(doc, name: name)
                app.notice("PDF Oluştur: \(name) (\(doc.pageCount) sayfa) yeni sekmede açıldı.")
                dismiss()
            } catch {
                state = .failed(error.localizedDescription)
            }
        }
    }
}

// MARK: - Hassas bilgileri kaldır

struct SanitizeToolView: View {
    @EnvironmentObject var app: AppState
    @State var files: [URL]
    @State private var opts = SanitizeOptions()
    @State private var state: ToolRunState = .idle

    var body: some View {
        ToolScaffold(kind: .sanitize, runTitle: "Temizle", canRun: !files.isEmpty, state: state, run: run) {
            FileListEditor(files: $files, types: [.pdf], multiple: true, title: "PDF'ler")
            VStack(alignment: .leading, spacing: 6) {
                Toggle("Meta veriler (yazar, başlık, oluşturan uygulama, XMP)", isOn: $opts.metadata)
                Toggle("Yorumlar ve açıklamalar", isOn: $opts.comments)
                Toggle("Gömülü dosyalar ve ekler", isOn: $opts.attachments)
                Toggle("Gömülü komut dosyaları (JavaScript) ve eylemler", isOn: $opts.scripts)
                Toggle("Form alanı değerleri", isOn: $opts.formData)
                Toggle("Bağlantılar", isOn: $opts.links)
            }
            Text("Çıktılar \"_temiz\" ekiyle kaydedilir. Görünen metni kaldırmak için PDF'de Sansürle aracını kullanın.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private func run() {
        let inputs = files
        var folder: URL?
        if inputs.contains(where: { ToolIO.isTemporary($0) }) {
            guard let f = Dialogs.chooseFolder() else { return }
            folder = f
        }
        let o = opts
        let outFolder = folder
        state = .running("Temizleniyor…")
        Task { @MainActor in
            var outs: [URL] = []
            var report: [String] = []
            for input in inputs {
                let out = outFolder.map { $0.appendingPathComponent(input.baseName + "_temiz.pdf") } ?? input.uniqueSibling(suffix: "_temiz", ext: "pdf")
                do {
                    let lines = try await Task.detached(priority: .userInitiated) {
                        try PDFSanitizeService.sanitize(input: input, data: nil, output: out, options: o)
                    }.value
                    outs.append(out)
                    report.append("\(input.lastPathComponent):\n  • " + lines.joined(separator: "\n  • "))
                } catch {
                    report.append("\(input.lastPathComponent): \(error.localizedDescription)")
                }
            }
            state = outs.isEmpty ? .failed(report.joined(separator: "\n")) : .done(report.joined(separator: "\n"), outs)
            if !outs.isEmpty { app.notice("Hassas Bilgileri Kaldır: \(outs.count) dosya temizlendi.", urls: outs) }
        }
    }
}

// MARK: - Sertifika ile imzala

struct CertificateSignView: View {
    @EnvironmentObject var app: AppState
    let sessionID: UUID?
    @State private var identities: [SigningIdentity] = []
    @State private var selectedID: UUID?
    @State private var pageIndex = 0
    @State private var corner: CertificateSignService.Corner = .bottomRight
    @State private var reason = "Belgeyi onaylıyorum"
    @State private var location = ""
    @State private var visible = true
    @State private var state: ToolRunState = .idle
    @State private var loaded = false

    private var session: DocumentSession? { app.session(id: sessionID) }

    var body: some View {
        ToolScaffold(kind: .certificateSign, runTitle: "İmzala ve Kaydet", canRun: selectedID != nil && session != nil, state: state, run: run) {
            if let s = session {
                Text("Belge: \(s.displayName)").font(.callout)
            }
            if !loaded {
                ProgressView("Sertifikalar aranıyor…")
            } else if identities.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Label("Anahtar Zinciri'nde imzalama sertifikası bulunamadı", systemImage: "exclamationmark.triangle")
                        .font(.headline)
                    Text("Dijital imza için özel anahtarı olan bir sertifika gerekir (ör. nitelikli e-imza, kurumsal sertifika veya .p12 dosyası). Sertifikanızı Anahtar Zinciri Erişimi uygulamasına aktarın; deneme için Anahtar Zinciri Erişimi > Sertifika Asistanı > Sertifika Oluştur yolunu kullanabilirsiniz.")
                        .font(.callout).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Button("Yeniden Tara") { load() }
                }
            } else {
                Picker("Sertifika", selection: $selectedID) {
                    ForEach(identities) { i in
                        Text(i.name + (i.issuer.isEmpty ? "" : " — \(i.issuer)")).tag(Optional(i.id))
                    }
                }
                if let i = identities.first(where: { $0.id == selectedID }), let exp = i.expires {
                    Text("Geçerlilik sonu: \(Fmt.shortDate(exp))" + (exp < Date() ? " (SÜRESİ DOLMUŞ)" : ""))
                        .font(.caption).foregroundStyle(exp < Date() ? Color.red : Color.secondary)
                }
                TextField("Neden", text: $reason).textFieldStyle(.roundedBorder)
                TextField("Yer (isteğe bağlı)", text: $location).textFieldStyle(.roundedBorder)
                Toggle("Görünür imza kutusu ekle", isOn: $visible)
                if visible, let s = session {
                    HStack {
                        Stepper("Sayfa: \(pageIndex + 1) / \(s.pageCount)", value: $pageIndex, in: 0...max(0, s.pageCount - 1))
                        Picker("Konum", selection: $corner) {
                            ForEach(CertificateSignService.Corner.allCases) { Text($0.rawValue).tag($0) }
                        }
                        .frame(width: 180)
                    }
                }
                Text("İmzalanan dosyayı daha sonra başka bir uygulamada değiştirmek imzayı geçersiz kılar. macOS, anahtarınızı kullanmak için izin isteyebilir.")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .onAppear {
            if let s = session { pageIndex = max(0, s.pageCount - 1) }
            load()
        }
    }

    private func load() {
        identities = CertificateSignService.availableIdentities()
        if selectedID == nil { selectedID = identities.first?.id }
        loaded = true
    }

    private func run() {
        guard let s = session, let ident = identities.first(where: { $0.id == selectedID }) else { return }
        let base = s.url?.baseName ?? s.displayName.replacingOccurrences(of: ".pdf", with: "")
        guard let out = Dialogs.save(suggestedName: base + "_imzalı.pdf", type: .pdf, title: "İmzalı PDF'yi kaydet",
                                     directory: s.url?.deletingLastPathComponent()) else { return }
        state = .running("İmzalanıyor…")
        Task { @MainActor in
            do {
                guard let data = s.currentData(), let doc = PDFDocument(data: data) else {
                    throw QPDFError.message("Belge hazırlanamadı.")
                }
                if visible {
                    CertificateSignService.stampAppearance(doc: doc, pageIndex: pageIndex, corner: corner,
                                                           signer: ident.name, reason: reason, location: location)
                }
                guard let prepared = doc.dataRepresentation() else { throw QPDFError.message("Belge hazırlanamadı.") }
                let signed = try CertificateSignService.sign(pdf: prepared, identity: ident.identity, name: ident.name,
                                                             reason: reason, location: location)
                try signed.write(to: out, options: .atomic)
                state = .done("Belge \"\(ident.name)\" sertifikasıyla imzalandı. İmzayı doğrulamak için dosyayı Adobe Acrobat Reader'da açabilirsiniz.", [out])
                app.notice("Sertifika ile İmzala: \(out.lastPathComponent)", urls: [out])
            } catch {
                state = .failed(error.localizedDescription)
            }
        }
    }
}
