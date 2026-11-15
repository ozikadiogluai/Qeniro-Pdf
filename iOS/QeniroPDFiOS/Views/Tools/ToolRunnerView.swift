import SwiftUI
import PhotosUI
import PDFKit
import UniformTypeIdentifiers

/// Araçlar sekmesinden seçilen dosya(lar) için seçenekler ve sonuç.
struct ToolRunnerView: View {
    @EnvironmentObject private var app: AppModel
    @Environment(\.dismiss) private var dismiss
    @State var run: ToolRun
    @State private var data: Data?
    @State private var loadError: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    content
                }
                .padding(16)
            }
            .background(Theme.background)
            .navigationTitle(run.tool.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("Kapat") { dismiss() } }
            }
        }
        .task {
            guard run.tool != .merge, let u = run.urls.first else { return }
            do {
                data = try SecurityScope.access(u) { try Data(contentsOf: u) }
            } catch {
                loadError = error.localizedDescription
            }
        }
    }

    private var fileName: String { run.urls.first?.lastPathComponent ?? "Belge.pdf" }

    @ViewBuilder private var content: some View {
        if run.tool == .merge {
            MergeForm(urls: $run.urls)
        } else if let loadError {
            Text(loadError).foregroundStyle(Theme.accent)
        } else if let data {
            HStack(spacing: 12) {
                PDFBadge()
                VStack(alignment: .leading, spacing: 2) {
                    Text(fileName).font(.system(size: 15, weight: .semibold)).lineLimit(1).truncationMode(.middle)
                    Text(Fmt.fileSize(Int64(data.count))).font(.system(size: 12.5)).foregroundStyle(Theme.secondary)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .card()
            switch run.tool {
            case .split: SplitForm(data: data, name: fileName)
            case .compress: CompressForm(data: data, name: fileName)
            case .protect: ProtectForm(data: data, name: fileName)
            case .toWord: ConvertPanel(name: fileName, dataProvider: { data }, preset: .word)
            case .toExcel: ConvertPanel(name: fileName, dataProvider: { data }, preset: .excel)
            case .toPowerPoint: ConvertPanel(name: fileName, dataProvider: { data }, preset: .powerpoint)
            default: ConvertPanel(name: fileName, dataProvider: { data })
            }
        } else {
            ProgressView().frame(maxWidth: .infinity).padding(40)
        }
    }
}

/// Dosyaları birleştir: sıralanabilir liste + ekle + birleştir.
struct MergeForm: View {
    @Binding var urls: [URL]
    @StateObject private var job = ToolJob()
    @State private var showImporter = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Sırayı değiştirmek için oklara dokunun. Dosyalar bu sırayla tek PDF olur.")
                .font(.system(size: 13))
                .foregroundStyle(Theme.secondary)
            VStack(spacing: 0) {
                ForEach(Array(urls.enumerated()), id: \.offset) { i, u in
                    HStack(spacing: 10) {
                        PDFBadge().scaleEffect(0.8).frame(width: 30, height: 36)
                        Text(u.lastPathComponent).font(.system(size: 14.5)).lineLimit(1).truncationMode(.middle)
                        Spacer()
                        Button { move(i, -1) } label: { Image(systemName: "chevron.up") }.disabled(i == 0)
                        Button { move(i, 1) } label: { Image(systemName: "chevron.down") }.disabled(i == urls.count - 1)
                        Button(role: .destructive) { urls.remove(at: i) } label: { Image(systemName: "minus.circle") }
                    }
                    .buttonStyle(.borderless)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    if i < urls.count - 1 { Rectangle().fill(Theme.divider).frame(height: 1) }
                }
            }
            .card()
            OutlineButton(title: "Dosya ekle", icon: "plus") { showImporter = true }
            PrimaryButton(title: "\(urls.count) dosyayı birleştir", busy: job.running) {
                guard urls.count >= 2 else { job.error = "Birleştirmek için en az iki PDF seçin."; return }
                let list = urls
                job.run {
                    let folder = try DocTools.freshOutputFolder()
                    let out = folder.appendingPathComponent("Birleştirilmiş.pdf")
                    let n = try PDFMergeService.merge(list, to: out)
                    return ToolOutput(urls: [out], note: "\(list.count) dosya, toplam \(n) sayfa.")
                }
            }
            if let e = job.error { Text(e).font(.system(size: 13)).foregroundStyle(Theme.accent) }
            if let out = job.output { ToolResultView(output: out) }
        }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.pdf], allowsMultipleSelection: true) { result in
            if case .success(let more) = result { urls.append(contentsOf: more) }
        }
    }

    private func move(_ i: Int, _ d: Int) {
        let j = i + d
        guard j >= 0, j < urls.count else { return }
        urls.swapAt(i, j)
    }
}

/// PDF Oluştur: kamerayla tara, fotoğraflardan, dosyadan (metin, RTF, HTML), boş belge.
struct CreatePDFView: View {
    @EnvironmentObject private var app: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var photoItems: [PhotosPickerItem] = []
    @State private var ocr = true
    @State private var showFileImporter = false
    @State private var working = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button {
                        dismiss()
                        Task { @MainActor in
                            try? await Task.sleep(nanoseconds: 400_000_000)
                            if DocumentScannerView.isSupported { app.showScanner = true }
                            else { app.errorMessage = "Bu cihazda belge tarayıcı kullanılamıyor." }
                        }
                    } label: { Label("Kamerayla belge tara", systemImage: "doc.viewfinder") }
                    PhotosPicker(selection: $photoItems, maxSelectionCount: 50, matching: .images) {
                        Label("Fotoğraflardan PDF", systemImage: "photo.on.rectangle")
                    }
                    Toggle("Fotoğraflardaki metni tanı (OCR)", isOn: $ocr)
                }
                Section {
                    Button { showFileImporter = true } label: {
                        Label("Metin, RTF veya HTML dosyasından", systemImage: "doc.richtext")
                    }
                    Button {
                        finish(PDFCreateService.blank(), name: "Yeni belge")
                    } label: { Label("Boş sayfa", systemImage: "doc") }
                } footer: {
                    Text("Oluşturulan PDF'ler Dosyalar uygulamasında \"iPhone'umda > Qeniro PDF\" klasörüne kaydedilir.")
                }
            }
            .disabled(working)
            .overlay { if working { ProgressView("Hazırlanıyor…").padding().background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12)) } }
            .navigationTitle("PDF Oluştur")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Kapat") { dismiss() } } }
        }
        .onChange(of: photoItems) { _, items in
            guard !items.isEmpty else { return }
            working = true
            let useOCR = ocr
            Task {
                var images: [UIImage] = []
                for it in items {
                    if let d = try? await it.loadTransferable(type: Data.self), let img = UIImage(data: d) { images.append(img) }
                }
                photoItems = []
                let doc = PDFCreateService.fromImages(images, ocr: useOCR)
                working = false
                guard doc.pageCount > 0 else { app.errorMessage = "Seçilen fotoğraflar okunamadı."; return }
                finish(doc, name: "Fotoğraflar")
            }
        }
        .fileImporter(isPresented: $showFileImporter,
                      allowedContentTypes: [.plainText, .rtf, .html, .rtfd, .utf8PlainText],
                      allowsMultipleSelection: false) { result in
            guard case .success(let urls) = result, let u = urls.first else { return }
            do {
                let doc = try PDFCreateService.fromDocument(at: u)
                finish(doc, name: u.deletingPathExtension().lastPathComponent)
            } catch {
                app.errorMessage = error.localizedDescription
            }
        }
    }

    private func finish(_ doc: PDFDocument, name: String) {
        dismiss()
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 400_000_000)
            app.saveAndOpen(doc, name: name)
        }
    }
}
