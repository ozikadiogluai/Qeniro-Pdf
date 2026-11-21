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
            VStack(alignment: .leading, spacing: 8) {
                ToolPanelHeader(title: String(localized: "Düzenle"), onClose: { session.panel = nil })

                if session.tool == .editText || session.selectedTextItem != nil || selectedFreeText != nil {
                    PanelCard(title: String(localized: "Metin")) {
                        TextPropertiesBox(session: session)
                        if let a = selectedFreeText {
                            Text("Metin kutusu içeriği").font(.callout).foregroundStyle(Theme.secondaryText)
                            TextEditor(text: Binding(get: { a.contents ?? "" },
                                                     set: { session.setContents($0, of: a) }))
                                .font(.body)
                                .frame(height: 80)
                                .focused($contentFocused)
                                .scrollContentBackground(.hidden)
                                .padding(4)
                                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.card2))
                        }
                        if session.selectedAnnotation != nil || session.selectedTextItem != nil {
                            Button(role: .destructive) {
                                if session.selectedAnnotation != nil { session.deleteSelected() } else { session.deleteSelectedTextItem() }
                            } label: {
                                Label(session.selectedTextItem != nil && session.selectedAnnotation == nil ? String(localized: "Seçili metin satırını sil") : String(localized: "Seçili öğeyi sil"),
                                      systemImage: "trash")
                            }
                            .buttonStyle(QSecondaryButtonStyle(fullWidth: true, foreground: Theme.red))
                        }
                    }
                }

                PanelCard(title: String(localized: "İçerik ekle"), spacing: 0, padding: 6) {
                    ToolListRow(symbol: "textformat", title: String(localized: "Metin"), active: session.tool == .editText,
                                trailing: session.tool == .editText ? String(localized: "seçili") : nil) {
                        session.tool = .editText
                    }
                    PanelDivider()
                    ToolListRow(symbol: "photo", title: String(localized: "Görüntü"), active: session.tool == .addImage) {
                        if let u = Dialogs.openFiles(types: [.image], multiple: false, title: String(localized: "Görsel seçin")).first,
                           let img = NSImage(contentsOf: u) {
                            session.pendingImage = img
                            session.tool = .addImage
                        }
                    }
                    PanelDivider()
                    ToolListRow(symbol: "menubar.rectangle", title: String(localized: "Üstbilgi ve altbilgi"), trailing: "›") {
                        session.panel = .headerFooter
                    }
                    PanelDivider()
                    ToolListRow(symbol: "drop", title: String(localized: "Filigran"), trailing: "›") {
                        session.panel = .watermark
                    }
                    PanelDivider()
                    ToolListRow(symbol: "link", title: String(localized: "Bağlantı"), active: session.tool == .addLink, trailing: "›") {
                        session.tool = .addLink
                    }
                    PanelDivider()
                    ToolListRow(symbol: showMoreContent ? "chevron.up" : "ellipsis", title: showMoreContent ? String(localized: "Daha az") : String(localized: "Diğer")) {
                        withAnimation(.easeInOut(duration: 0.15)) { showMoreContent.toggle() }
                    }
                    if showMoreContent {
                        ToolListRow(symbol: "character.textbox", title: String(localized: "Serbest metin kutusu (yorum katmanı)"), active: session.tool == .addText) {
                            session.tool = .addText
                        }
                        ToolListRow(symbol: "rectangle.on.rectangle", title: String(localized: "Seçili metni örtüp yeniden yaz")) {
                            if session.pdfView.currentSelection == nil {
                                session.tool = .select
                                Dialogs.info(String(localized: "Önce metni seçin"), String(localized: "Seçim aracı açıldı. Değiştirmek istediğiniz metni sürükleyerek seçin, sonra bu düğmeye tekrar basın."))
                            } else {
                                session.replaceSelectedText()
                            }
                        }
                        Text("Yedek yöntem: özgün metnin üstü beyaz kutuyla örtülür. Gerçek düzenleme için \"Metin\" aracını kullanın.")
                            .font(.callout).foregroundStyle(Theme.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                    }
                }

                PanelCard(title: String(localized: "Sayfa")) {
                    HStack(spacing: 6) {
                        SquareIconButton(symbol: "rotate.right", help: String(localized: "Sayfayı sağa döndür (90°)")) {
                            session.rotateCurrent(by: 90)
                        }
                        SquareIconButton(symbol: "crop", help: String(localized: "Kırp: sayfada tutulacak alanı sürükleyin"), active: session.tool == .crop) {
                            session.tool = .crop
                        }
                        SquareIconButton(symbol: "trash", help: String(localized: "Geçerli sayfayı sil"), destructive: true) {
                            if Dialogs.confirm(String(localized: "Sayfa \(session.currentPageIndex + 1) silinsin mi?"), String(localized: "Bu işlemi ⌘Z ile geri alabilirsiniz."), ok: String(localized: "Sil")) {
                                session.deletePages([session.currentPageIndex])
                            }
                        }
                        SquareIconButton(symbol: "rectangle.portrait.and.arrow.right", help: String(localized: "Sayfayı çıkar (yeni PDF olarak kaydet)")) {
                            session.extractPages([session.currentPageIndex])
                        }
                    }
                    Button("Sayfaları organize et") { app.perform(.organize) }
                        .buttonStyle(QSecondaryButtonStyle(height: 34, fullWidth: true))
                }

                PanelCard(title: String(localized: "Diğer seçenekler"), spacing: 0, padding: 6) {
                    ToolListRow(symbol: "square.on.square", title: String(localized: "Dosyaları birleştir")) { app.perform(.merge) }
                    ToolListRow(symbol: "eye.slash", title: String(localized: "PDF'ye Redaksiyon Yap")) { app.perform(.redact) }
                    ToolListRow(symbol: "list.bullet.rectangle", title: String(localized: "Form hazırla")) { session.panel = .formPrepare }
                }
            }
            .padding(12)
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
                Menu {
                    Picker("Yazı tipi", selection: Binding(get: { session.textStyle.family },
                                                          set: { v in session.updateStyle { $0.family = v } })) {
                        ForEach(families, id: \.self) { f in
                            Text(f).tag(f)
                        }
                    }
                    .pickerStyle(.inline)
                } label: {
                    capsuleField(session.textStyle.family)
                }
                .menuStyle(.button)
                .buttonStyle(.plain)
                .menuIndicator(.hidden)
                .accessibilityLabel("Yazı tipi")
                Menu {
                    Picker("Boyut", selection: Binding(get: { session.textStyle.size },
                                                       set: { v in session.updateStyle { $0.size = v } })) {
                        ForEach(sizes, id: \.self) { s in
                            Text(sizeLabel(s)).tag(s)
                        }
                    }
                    .pickerStyle(.inline)
                } label: {
                    capsuleField(sizeLabel(session.textStyle.size))
                }
                .menuStyle(.button)
                .buttonStyle(.plain)
                .menuIndicator(.hidden)
                .frame(width: 66)
                .accessibilityLabel("Yazı boyutu")
            }
            HStack(spacing: 6) {
                ToggleGlyph(label: Text("B").bold(), isOn: session.textStyle.bold) { session.updateStyle { $0.bold.toggle() } }
                    .accessibilityLabel("Kalın")
                ToggleGlyph(label: Text("I").italic(), isOn: session.textStyle.italic) { session.updateStyle { $0.italic.toggle() } }
                    .accessibilityLabel("İtalik")
                ToggleGlyph(label: Text("U").underline(), isOn: session.textStyle.underline) { session.updateStyle { $0.underline.toggle() } }
                    .accessibilityLabel("Altı çizili")
                ColorPicker("", selection: Binding(get: { session.textStyle.color },
                                                   set: { c in session.updateStyle { $0.color = c } }),
                            supportsOpacity: false)
                    .labelsHidden()
                    .frame(width: 36, height: 32)
                    .background(Capsule().fill(Theme.card2))
                    .help("Metin rengi")
                    .accessibilityLabel("Metin rengi")
                Spacer(minLength: 0)
            }
            HStack(spacing: 6) {
                alignButton(.left, "text.alignleft")
                alignButton(.center, "text.aligncenter")
                alignButton(.right, "text.alignright")
                if session.selectedAnnotation != nil {
                    alignButton(.justified, "text.justify")
                }
            }
            Text(session.selectedTextItem != nil && session.selectedAnnotation == nil
                 ? String(localized: "Değişiklikler seçili satıra uygulanır. Yazı tipi değişirse satır seçilen sistem yazı tipiyle yeniden yazılır.")
                 : String(localized: "Seçim yokken bu ayarlar yeni eklenecek metne uygulanır."))
                .font(.callout)
                .foregroundStyle(Theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func capsuleField(_ text: String) -> some View {
        HStack(spacing: 4) {
            Text(text).lineLimit(1).foregroundStyle(Theme.text)
            Spacer(minLength: 2)
            Image(systemName: "chevron.up.chevron.down")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(Theme.secondaryText)
        }
        .font(.body)
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, minHeight: 32)
        .background(Capsule().fill(Theme.card2))
        .contentShape(Capsule())
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
                ToolPanelHeader(title: String(localized: "PDF'yi redakte et"),
                                onBack: { session.panel = .tab; session.tool = .select },
                                onClose: { session.panel = nil; session.tool = .select })
                PanelCard(spacing: 10) {
                Text("İşaretlenen alanlar uygulandığında kalıcı olarak kaldırılır; yalnızca üstü örtülmez.")
                    .font(.callout).foregroundStyle(Theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)

                PanelSectionTitle(String(localized: "İşaretle"))
                PanelRow(symbol: "rectangle.dashed", title: String(localized: "Alan işaretle"), active: session.tool == .redact) {
                    session.tool = .redact
                }
                PanelRow(symbol: "text.badge.xmark", title: String(localized: "Seçili metni işaretle")) {
                    if let sel = session.pdfView.currentSelection {
                        lastMarked = session.markRedactions(for: [sel])
                        session.pdfView.clearSelection()
                    } else {
                        session.tool = .select
                        Dialogs.info(String(localized: "Metin seçilmedi"), String(localized: "Önce seçim aracıyla metni seçin."))
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

                Rectangle().fill(Theme.divider).frame(height: 1).padding(.vertical, 4)

                PanelSectionTitle(String(localized: "Uygula"))
                Text("Toplam \(session.redactionMarkCount) işaret").font(.caption).foregroundStyle(.secondary)
                Toggle("Kalan metni seçilebilir tut (OCR)", isOn: $restoreText)
                    .font(.callout)
                Button {
                    session.applyRedactions(restoreText: restoreText)
                    lastMarked = nil
                } label: {
                    Label("Sansürü Uygula", systemImage: "eye.slash").frame(maxWidth: .infinity)
                }
                .buttonStyle(QDestructiveButtonStyle(fullWidth: true))
                Text("İşaretli sayfalar yüksek çözünürlüklü görüntüye dönüştürülür; işaretli içerik dosyada hiçbir biçimde kalmaz. Kaydetmeyi unutmayın.")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(12)
        }
    }

    private func markAll() {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return }
        let results = session.document.findString(q, withOptions: [.caseInsensitive, .diacriticInsensitive])
        lastMarked = session.markRedactions(for: results)
    }
}
