import SwiftUI
import AppKit
import PDFKit
import UniformTypeIdentifiers

/// "Düzenle" sekmesi: Sayfayı değiştir, İçerik ekle (gerçek metin düzenleme dahil), Diğer seçenekler.
struct EditTabPanel: View {
    @EnvironmentObject var app: AppState
    @ObservedObject var session: DocumentSession
    @FocusState private var contentFocused: Bool
    @State private var showMoreContent = false

    private var selectedFreeText: PDFAnnotation? {
        guard let a = session.selectedAnnotation, a.isFreeText else { return nil }
        return a
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 2) {
                ToolPanelHeader(title: "Düzenle", onClose: { session.panel = nil })

                PanelCapsTitle("SAYFAYI DEĞİŞTİR")
                HStack(spacing: 6) {
                    SquareIconButton(symbol: "rotate.right", help: "Sayfayı sağa döndür (90°)") {
                        session.rotateCurrent(by: 90)
                    }
                    SquareIconButton(symbol: "crop", help: "Kırp: sayfada tutulacak alanı sürükleyin", active: session.tool == .crop) {
                        session.tool = .crop
                    }
                    SquareIconButton(symbol: "trash", help: "Geçerli sayfayı sil") {
                        if Dialogs.confirm("Sayfa \(session.currentPageIndex + 1) silinsin mi?", "Bu işlemi ⌘Z ile geri alabilirsiniz.", ok: "Sil") {
                            session.deletePages([session.currentPageIndex])
                        }
                    }
                    SquareIconButton(symbol: "rectangle.portrait.and.arrow.right", help: "Sayfayı çıkar (yeni PDF olarak kaydet)") {
                        session.extractPages([session.currentPageIndex])
                    }
                }
                .padding(.horizontal, 6)
                .padding(.bottom, 4)
                ToolListRow(symbol: "square.grid.2x2", title: "Sayfaları organize et") { app.perform(.organize) }

                PanelCapsTitle("İÇERİK EKLE")
                ToolListRow(symbol: "textformat", title: "Metin", active: session.tool == .editText,
                            trailing: session.tool == .editText ? "seçili" : nil) {
                    session.tool = .editText
                }
                if session.tool == .editText || session.selectedTextItem != nil || selectedFreeText != nil {
                    TextPropertiesBox(session: session)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 4)
                }
                if let a = selectedFreeText {
                    Text("Metin kutusu içeriği").font(.caption).foregroundStyle(.secondary).padding(.horizontal, 8)
                    TextEditor(text: Binding(get: { a.contents ?? "" },
                                             set: { session.setContents($0, of: a) }))
                        .font(.system(size: 12))
                        .frame(height: 80)
                        .focused($contentFocused)
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Theme.border))
                        .padding(.horizontal, 4)
                }
                ToolListRow(symbol: "photo", title: "Görüntü", active: session.tool == .addImage) {
                    if let u = Dialogs.openFiles(types: [.image], multiple: false, title: "Görsel seçin").first,
                       let img = NSImage(contentsOf: u) {
                        session.pendingImage = img
                        session.tool = .addImage
                    }
                }
                ToolListRow(symbol: "menubar.rectangle", title: "Üstbilgi ve altbilgi", trailing: "›") {
                    session.panel = .headerFooter
                }
                ToolListRow(symbol: "drop", title: "Filigran", trailing: "›") {
                    session.panel = .watermark
                }
                ToolListRow(symbol: "link", title: "Bağlantı", active: session.tool == .addLink, trailing: "›") {
                    session.tool = .addLink
                }
                Button(showMoreContent ? "Daha az" : "Diğer") {
                    withAnimation(.easeInOut(duration: 0.15)) { showMoreContent.toggle() }
                }
                .buttonStyle(.link)
                .font(.system(size: 14))
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                if showMoreContent {
                    ToolListRow(symbol: "character.textbox", title: "Serbest metin kutusu (yorum katmanı)", active: session.tool == .addText) {
                        session.tool = .addText
                    }
                    ToolListRow(symbol: "rectangle.on.rectangle", title: "Seçili metni örtüp yeniden yaz") {
                        if session.pdfView.currentSelection == nil {
                            session.tool = .select
                            Dialogs.info("Önce metni seçin", "Seçim aracı açıldı. Değiştirmek istediğiniz metni sürükleyerek seçin, sonra bu düğmeye tekrar basın.")
                        } else {
                            session.replaceSelectedText()
                        }
                    }
                    Text("Yedek yöntem: özgün metnin üstü beyaz kutuyla örtülür. Gerçek düzenleme için \"Metin\" aracını kullanın.")
                        .font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 8)
                }
                if session.selectedAnnotation != nil || session.selectedTextItem != nil {
                    Button(role: .destructive) {
                        if session.selectedAnnotation != nil { session.deleteSelected() } else { session.deleteSelectedTextItem() }
                    } label: {
                        Label(session.selectedTextItem != nil && session.selectedAnnotation == nil ? "Seçili metin satırını sil" : "Seçili öğeyi sil",
                              systemImage: "trash")
                    }
                    .padding(.horizontal, 8)
                    .padding(.top, 6)
                }

                PanelCapsTitle("DİĞER SEÇENEKLER")
                ToolListRow(symbol: "square.on.square", title: "Dosyaları birleştir", bold: true) { app.perform(.merge) }
                ToolListRow(symbol: "eye.slash", title: "PDF'ye Redaksiyon Yap", bold: true) { app.perform(.redact) }
                ToolListRow(symbol: "list.bullet.rectangle", title: "Form hazırla", bold: true) { session.panel = .formPrepare }
            }
            .padding(16)
        }
        .onChange(of: session.focusTextRequest) { _, _ in
            Task { @MainActor in contentFocused = true }
        }
    }
}

/// Metin özellikleri: yazı tipi, boyut, B/I/U, renk, hizalama. Seçili gerçek metne (PDFium)
/// veya seçili metin kutusuna uygulanır; seçim yoksa yeni eklenecek metnin biçimidir.
struct TextPropertiesBox: View {
    @ObservedObject var session: DocumentSession

    private var families: [String] {
        var f = TextStyle.families
        if !f.contains(session.textStyle.family) { f.insert(session.textStyle.family, at: 0) }
        return f
    }

    private var sizes: [CGFloat] {
        var s = TextStyle.sizes
        if !s.contains(session.textStyle.size) {
            s.append(session.textStyle.size)
            s.sort()
        }
        return s
    }

    private func sizeLabel(_ v: CGFloat) -> String {
        v == v.rounded() ? "\(Int(v))" : String(format: "%.1f", Double(v))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Picker("", selection: Binding(get: { session.textStyle.family },
                                              set: { v in session.updateStyle { $0.family = v } })) {
                    ForEach(families, id: \.self) { f in
                        Text(f).tag(f)
                    }
                }
                .labelsHidden()
                Picker("", selection: Binding(get: { session.textStyle.size },
                                              set: { v in session.updateStyle { $0.size = v } })) {
                    ForEach(sizes, id: \.self) { s in
                        Text(sizeLabel(s)).tag(s)
                    }
                }
                .labelsHidden()
                .frame(width: 66)
            }
            HStack(spacing: 4) {
                ToggleGlyph(label: Text("B").bold(), isOn: session.textStyle.bold) { session.updateStyle { $0.bold.toggle() } }
                ToggleGlyph(label: Text("I").italic(), isOn: session.textStyle.italic) { session.updateStyle { $0.italic.toggle() } }
                ToggleGlyph(label: Text("U").underline(), isOn: session.textStyle.underline) { session.updateStyle { $0.underline.toggle() } }
                Spacer()
                ColorPicker("", selection: Binding(get: { session.textStyle.color },
                                                   set: { c in session.updateStyle { $0.color = c } }),
                            supportsOpacity: false)
                    .labelsHidden()
                    .help("Metin rengi")
            }
            HStack(spacing: 4) {
                alignButton(.left, "text.alignleft")
                alignButton(.center, "text.aligncenter")
                alignButton(.right, "text.alignright")
                if session.selectedAnnotation != nil {
                    alignButton(.justified, "text.justify")
                }
            }
            Text(session.selectedTextItem != nil && session.selectedAnnotation == nil
                 ? "Değişiklikler seçili satıra uygulanır. Yazı tipi değişirse satır seçilen sistem yazı tipiyle yeniden yazılır."
                 : "Seçim yokken bu ayarlar yeni eklenecek metne uygulanır.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.border))
    }

    private func alignButton(_ alignment: NSTextAlignment, _ symbol: String) -> some View {
        ToggleGlyph(label: Text(Image(systemName: symbol)), isOn: session.textStyle.alignment == alignment) {
            session.updateStyle { $0.alignment = alignment }
        }
    }
}

/// "PDF'yi redakte et" paneli.
struct RedactPanel: View {
    @ObservedObject var session: DocumentSession
    @State private var query = ""
    @State private var restoreText = true
    @State private var lastMarked: Int?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                ToolPanelHeader(title: "PDF'yi redakte et",
                                onBack: { session.panel = .tab; session.tool = .select },
                                onClose: { session.panel = nil; session.tool = .select })
                Text("İşaretlenen alanlar uygulandığında kalıcı olarak kaldırılır; yalnızca üstü örtülmez.")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                PanelSectionTitle("İşaretle")
                PanelRow(symbol: "rectangle.dashed", title: "Alan işaretle", active: session.tool == .redact) {
                    session.tool = .redact
                }
                PanelRow(symbol: "text.badge.xmark", title: "Seçili metni işaretle") {
                    if let sel = session.pdfView.currentSelection {
                        lastMarked = session.markRedactions(for: [sel])
                        session.pdfView.clearSelection()
                    } else {
                        session.tool = .select
                        Dialogs.info("Metin seçilmedi", "Önce seçim aracıyla metni seçin.")
                    }
                }
                Text("Ara ve tümünü işaretle").font(.caption).foregroundStyle(.secondary)
                HStack {
                    TextField("ör. TC kimlik no, IBAN", text: $query)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit { markAll() }
                    Button("İşaretle") { markAll() }
                        .disabled(query.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                if let n = lastMarked {
                    Text("\(n) alan işaretlendi.").font(.caption).foregroundStyle(Theme.green)
                }

                Divider().padding(.vertical, 4)

                PanelSectionTitle("Uygula")
                Text("Toplam \(session.redactionMarkCount) işaret").font(.caption).foregroundStyle(.secondary)
                Toggle("Kalan metni seçilebilir tut (OCR)", isOn: $restoreText)
                    .font(.callout)
                Button {
                    session.applyRedactions(restoreText: restoreText)
                    lastMarked = nil
                } label: {
                    Label("Sansürü Uygula", systemImage: "eye.slash").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.accent)
                Text("İşaretli sayfalar yüksek çözünürlüklü görüntüye dönüştürülür; işaretli içerik dosyada hiçbir biçimde kalmaz. Kaydetmeyi unutmayın.")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(16)
        }
    }

    private func markAll() {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return }
        let results = session.document.findString(q, withOptions: [.caseInsensitive, .diacriticInsensitive])
        lastMarked = session.markRedactions(for: results)
    }
}
