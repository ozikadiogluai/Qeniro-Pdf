import SwiftUI
import PDFKit

/// PDF görüntüleyici: üst çubuk, sayfa alanı, yüzen araç çubuğu, alt sekmeler ve alt paneller.
struct ViewerView: View {
    @ObservedObject var session: DocumentSession
    @EnvironmentObject private var app: AppModel
    @EnvironmentObject private var library: FileLibrary
    @EnvironmentObject private var store: SignatureStore
    @State private var detent: PresentationDetent = .medium
    @State private var confirmExit = false
    @State private var share: ShareItem?
    @State private var commentText = ""
    @State private var linkText = ""
    @State private var showCreate = false
    @State private var confirmApplySign = false
    @FocusState private var searchFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            topBar
            if session.isSearching { searchBar }
            if let hint = currentHint { hintBand(hint) }
            ZStack(alignment: .bottom) {
                Theme.viewerBackground
                PDFCanvas(session: session)
                    .environment(\.layoutDirection, .leftToRight) // PDF sayfası dile göre aynalanmaz
                    .ignoresSafeArea(.keyboard)
                VStack(spacing: 10) {
                    if session.selectedAnnotation != nil && session.tool == .select { selectionBar }
                    if session.tool == .redact && session.redactionMarkCount > 0 { redactBar }
                }
                .padding(.bottom, 14)
            }
            .overlay(alignment: .trailing) {
                floatingToolbar
                    .padding(.trailing, 12)
            }
            bottomTabs
        }
        .background(Theme.viewerBackground.ignoresSafeArea())
        .sheet(item: $session.activeTab) { tab in
            panel(for: tab)
                .environmentObject(app)
                .environmentObject(library)
                .environmentObject(store)
                .presentationDetents(detents(for: tab), selection: $detent)
                .presentationBackgroundInteraction(.enabled(upThrough: .medium))
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(Theme.sheetRadius)
                .presentationBackground(Theme.background)
        }
        .sheet(isPresented: $session.showOrganizer) {
            PageOrganizerView(session: session)
        }
        .sheet(item: $share) { item in ActivityView(items: item.urls) }
        .sheet(isPresented: $showCreate) {
            CreatePDFView().environmentObject(app)
        }
        .background {
            // Görüntüleyici açıkken belge tarayıcı buradan sunulur (kök görünüm zaten bu ekranı sunuyor).
            Color.clear
                .fullScreenCover(isPresented: Binding(get: { app.showScanner }, set: { app.showScanner = $0 })) {
                    DocumentScannerView(onFinish: { images in
                        app.showScanner = false
                        app.finishScan(images)
                    }, onCancel: {
                        app.showScanner = false
                    })
                    .ignoresSafeArea()
                }
        }
        .confirmationDialog("Değişiklikler kaydedilsin mi?", isPresented: $confirmExit, titleVisibility: .visible) {
            Button("Kaydet ve kapat") {
                if session.save() { app.closeSession() }
            }
            Button("Kaydetmeden kapat", role: .destructive) { app.closeSession() }
            Button("Vazgeç", role: .cancel) {}
        } message: {
            Text("\"\(session.displayName)\" belgesinde kaydedilmemiş değişiklikler var.")
        }
        .confirmationDialog("Sayfayı kırp", isPresented: Binding(get: { session.pendingCropRect != nil },
                                                                set: { if !$0 { session.pendingCropRect = nil } }),
                            titleVisibility: .visible) {
            Button("Yalnızca bu sayfa") {
                if let p = session.pendingCropRect { session.cropPages([p.page], to: p.rect) }
            }
            Button("Tüm sayfalar") {
                if let p = session.pendingCropRect { session.cropPages(Array(0..<session.pageCount), to: p.rect) }
            }
            Button("Vazgeç", role: .cancel) {}
        } message: {
            Text("Seçilen alanın dışı gizlenir (kırpma kutusu).")
        }
        .alert("Yorum", isPresented: Binding(get: { session.pendingComment != nil },
                                            set: { if !$0 { session.pendingComment = nil } })) {
            TextField("Yorumunuz", text: $commentText)
            Button("Kaydet") {
                if let c = session.pendingComment { session.addComment(commentText, page: c.page, at: c.point) }
                commentText = ""
            }
            Button("Vazgeç", role: .cancel) { commentText = "" }
        }
        .alert("Bağlantı ekle", isPresented: Binding(get: { session.pendingLinkRect != nil },
                                                    set: { if !$0 { session.pendingLinkRect = nil } })) {
            TextField("https://ornek.com veya sayfa no", text: $linkText)
                .textInputAutocapitalization(.never)
                .keyboardType(.URL)
            Button("Ekle") {
                if let l = session.pendingLinkRect { session.addLink(linkText, page: l.page, rect: l.rect) }
                linkText = ""
            }
            Button("Vazgeç", role: .cancel) { linkText = "" }
        } message: {
            Text("Bağlantının açacağı web adresini veya gidilecek sayfa numarasını yazın.")
        }
        .alert("Bir sorun oluştu", isPresented: Binding(get: { session.errorMessage != nil },
                                                       set: { if !$0 { session.errorMessage = nil } })) {
            Button("Tamam", role: .cancel) {}
        } message: { Text(session.errorMessage ?? "") }
        .alert("Bilgi", isPresented: Binding(get: { session.infoMessage != nil },
                                            set: { if !$0 { session.infoMessage = nil } })) {
            Button("Tamam", role: .cancel) {}
        } message: { Text(session.infoMessage ?? "") }
        .confirmationDialog("İmzalar ve alanlar sayfaya gömülsün mü?", isPresented: $confirmApplySign, titleVisibility: .visible) {
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
        .overlay {
            if let msg = session.busyMessage { BusyOverlay(message: msg) }
        }
        .onChange(of: session.inlineTarget != nil) { _, editing in
            // Yerinde düzenleme başlayınca panel küçülsün; düzenlenen satır panelin altında kalmasın.
            if editing, session.activeTab != nil { detent = .height(220) }
        }
        .onChange(of: session.activeTab) { _, tab in
            if tab == .edit || tab == .sign { if detent == .large { detent = .medium } }
            if tab == nil, session.mode == nil, session.tool != .select, !keepToolWhenPanelCloses { session.tool = .select }
        }
    }

    /// Panel kapandığında araç seçili kalsın mı (yerleştirme araçları)?
    private var keepToolWhenPanelCloses: Bool {
        switch session.tool {
        case .redact, .comment, .link, .crop, .addImage, .placeSignature, .placeText, .placeCheck, .placeDate, .draw: return true
        default: return false
        }
    }

    private var currentHint: String? {
        if session.mode == .edit {
            return session.tool.hint ?? ViewerTool.editText.hint
        }
        return session.tool.hint
    }

    private func detents(for tab: ViewerTab) -> Set<PresentationDetent> {
        [.height(220), .medium, .large]
    }

    @ViewBuilder private func panel(for tab: ViewerTab) -> some View {
        switch tab {
        case .allTools:
            AllToolsPanel(session: session, detent: $detent, share: shareCopy, close: { session.activeTab = nil })
        case .edit:
            EditPanel(session: session, detent: $detent)
        case .convert:
            ScrollView {
                ConvertPanel(name: session.displayName,
                             dataProvider: { session.currentData() },
                             onClose: { session.activeTab = nil },
                             onCreatePDF: { session.activeTab = nil; showCreateAfterDelay() },
                             onCompress: nil,
                             onOCR: { session.activeTab = nil; session.runOCR(force: false) })
                    .padding(.horizontal, 12)
                    .padding(.top, 14)
                    .padding(.bottom, 24)
            }
            .background(Theme.background)
        case .sign:
            SignPanel(session: session, detent: $detent)
        }
    }

    private func showCreateAfterDelay() {
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 400_000_000)
            showCreate = true
        }
    }

    private func shareCopy() {
        if let u = session.exportTempCopy() {
            session.activeTab = nil
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 350_000_000)
                share = ShareItem(urls: [u])
            }
        } else {
            session.errorMessage = String(localized: "Belge paylaşım için hazırlanamadı.")
        }
    }

    // MARK: - Üst çubuk

    @ViewBuilder private var topBar: some View {
        HStack(spacing: 8) {
            switch session.mode {
            case .edit?:
                if session.activeTab == nil {
                    capsuleButton(String(localized: "Vazgeç")) { session.cancelMode() }
                } else {
                    Color.clear.frame(width: 44, height: 44)
                }
                titleBlock(title: String(localized: "Düzenle"), subtitle: session.displayName)
                Button { session.undo() } label: {
                    Image(systemName: "arrow.uturn.backward").font(.system(size: 17))
                        .foregroundStyle(session.canUndo ? Theme.text : Theme.chevron)
                        .frame(width: 44, height: 44)
                }
                .disabled(!session.canUndo)
                .qGlass(Circle())
                .accessibilityLabel("Geri al")
                if session.activeTab == nil {
                    capsuleButton(String(localized: "Kaydet"), primary: true) {
                        if session.save() { session.exitMode() }
                    }
                }
            case .sign?:
                if session.activeTab == nil {
                    capsuleButton(String(localized: "Vazgeç")) { session.cancelMode() }
                } else {
                    Color.clear.frame(width: 44, height: 44)
                }
                titleBlock(title: String(localized: "Doldur ve İmzala"), subtitle: String(localized: "Sayfa \(session.currentPageIndex + 1) / \(session.pageCount)"))
                if session.activeTab == nil {
                    capsuleButton(String(localized: "Uygula"), primary: true) { confirmApplySign = true }
                } else {
                    Color.clear.frame(width: 44, height: 44)
                }
            default:
                Button { close() } label: {
                    Image(systemName: "chevron.left").flipsForRightToLeftLayoutDirection(true)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Theme.text)
                        .frame(width: 44, height: 44)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .qGlass(Circle())
                .accessibilityLabel("Geri")
                titleBlock(title: session.displayName + (session.isDirty ? " •" : ""),
                           subtitle: String(localized: "Sayfa \(session.currentPageIndex + 1) / \(session.pageCount)"))
                HStack(spacing: 0) {
                    Button {
                        session.isSearching.toggle()
                        if session.isSearching { searchFocused = true } else { session.clearSearch() }
                    } label: {
                        Image(systemName: "magnifyingglass").font(.system(size: 17))
                            .foregroundStyle(Theme.text)
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Ara")
                    Button { shareCopy() } label: {
                        Image(systemName: "square.and.arrow.up").font(.system(size: 17))
                            .foregroundStyle(Theme.text)
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Paylaş")
                }
                .qGlassCapsule()
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 6)
        .padding(.bottom, 10)
        .background(
            LinearGradient(stops: [.init(color: Theme.viewerBackground.opacity(0.96), location: 0.55),
                                   .init(color: Theme.viewerBackground.opacity(0), location: 1)],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea(edges: .top)
        )
    }

    private func titleBlock(title: String, subtitle: String) -> some View {
        VStack(spacing: 1) {
            Text(title)
                .font(.headline)
                .foregroundStyle(Theme.text)
                .lineLimit(1)
                .truncationMode(.middle)
            Text(subtitle)
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(Theme.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .frame(maxWidth: .infinity)
    }

    private func capsuleButton(_ title: String, primary: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(primary ? .semibold : .regular))
                .foregroundStyle(primary ? Theme.onInk : Theme.text)
                .padding(.horizontal, 16)
                .frame(minHeight: 44)
                .background(primary ? Theme.ink : Theme.card, in: Capsule())
        }
        .buttonStyle(.plain)
    }

    private func close() {
        session.commitInlineIfNeeded()
        if session.isDirty { confirmExit = true } else { app.closeSession() }
    }

    private var searchBar: some View {
        HStack(spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundStyle(Theme.secondary).accessibilityHidden(true)
                TextField("Belgede ara", text: $session.searchText)
                    .focused($searchFocused)
                    .submitLabel(.search)
                    .onSubmit { session.search() }
            }
            .padding(.horizontal, 14)
            .frame(minHeight: 44)
            .background(Theme.card, in: Capsule())
            if !session.searchResults.isEmpty {
                Text("\(session.searchIndex + 1)/\(session.searchResults.count)")
                    .font(.footnote.monospacedDigit())
                    .foregroundStyle(Theme.secondary)
                Button { session.previousResult() } label: { Image(systemName: "chevron.up").frame(width: 36, height: 44) }
                    .accessibilityLabel("Önceki sonuç")
                Button { session.nextResult() } label: { Image(systemName: "chevron.down").frame(width: 36, height: 44) }
                    .accessibilityLabel("Sonraki sonuç")
            }
            Button("Bitti") {
                session.isSearching = false
                session.clearSearch()
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Theme.text)
            .frame(minHeight: 44)
        }
        .tint(Theme.text)
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
    }

    private func hintBand(_ text: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "info.circle")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.navy)
                .accessibilityHidden(true)
            Text(text)
                .font(.footnote)
                .foregroundStyle(Theme.text)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            if session.mode == nil && session.tool != .select {
                Button("Bitti") { session.tool = .select }
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.onInk)
                    .padding(.horizontal, 12)
                    .frame(minHeight: 32)
                    .background(Theme.ink, in: Capsule())
                    .frame(minHeight: 44)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
    }

    // MARK: - Yüzen araç çubuğu (cam, dikey)

    private var floatingToolbar: some View {
        VStack(spacing: 2) {
            toolButton("cursorarrow", String(localized: "Seç"), selected: session.tool == .select || session.tool == .editText && session.mode == nil) {
                session.tool = session.mode == .edit ? .editText : .select
            }
            toolButton("text.bubble", String(localized: "Yorum"), selected: session.tool == .comment) {
                session.tool = session.tool == .comment ? .select : .comment
            }
            toolButton("highlighter", String(localized: "Vurgula"), selected: false, accent: Theme.orange) {
                session.applyMarkup(.highlight)
            }
            toolButton("scribble.variable", String(localized: "Çiz"), selected: session.tool == .draw) {
                session.tool = session.tool == .draw ? .select : .draw
            }
            Menu {
                Button { session.applyMarkup(.underline) } label: { Label("Altını çiz", systemImage: "underline") }
                Button { session.applyMarkup(.strikeOut) } label: { Label("Üstünü çiz", systemImage: "strikethrough") }
                Menu {
                    ForEach(inkColors, id: \.0) { c in
                        Button(c.0) { session.inkColor = c.1 }
                    }
                } label: { Label("Çizim rengi", systemImage: "paintpalette") }
                Divider()
                Button { session.undo() } label: { Label("Geri al", systemImage: "arrow.uturn.backward") }
                    .disabled(!session.canUndo)
                Button { session.redo() } label: { Label("Yinele", systemImage: "arrow.uturn.forward") }
                    .disabled(!session.canRedo)
                if session.selectedAnnotation != nil {
                    Button(role: .destructive) { session.deleteSelected() } label: { Label("Seçili öğeyi sil", systemImage: "trash") }
                }
                Divider()
                Button {
                    if let u = session.url { library.toggleStar(u) }
                } label: {
                    Label(library.isStarred(session.url) ? String(localized: "Yıldızı kaldır") : String(localized: "Yıldızla"), systemImage: "star")
                }
                Button { session.rotateCurrent(by: 90) } label: { Label("Sayfayı döndür", systemImage: "rotate.right") }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Theme.text)
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel("Diğer araçlar")
        }
        .padding(4)
        .qGlassCapsule()
        .shadow(color: .black.opacity(0.12), radius: 10, x: 0, y: 6)
    }

    let inkColors: [(String, UIColor)] = [
        (String(localized: "Kırmızı"), UIColor(hex: 0xD23B2B)), (String(localized: "Lacivert"), UIColor(hex: 0x2E4A5E)), (String(localized: "Siyah"), UIColor(hex: 0x111111)),
        (String(localized: "Yeşil"), UIColor(hex: 0x178A4C)), (String(localized: "Turuncu"), UIColor(hex: 0xE07A1F))
    ]

    private func toolButton(_ icon: String, _ label: String, selected: Bool, accent: Color? = nil, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 17))
                .foregroundStyle(selected ? Theme.onInk : (accent ?? Theme.text))
                .frame(width: 44, height: 44)
                .background(selected ? Theme.ink : Color.clear, in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var selectionBar: some View {
        HStack(spacing: 4) {
            if let a = session.selectedAnnotation, a.isFreeText {
                smallButton(String(localized: "Düzenle"), "character.cursor.ibeam") { session.inlineTarget = .annotation(a) }
            }
            if let a = session.selectedAnnotation, a.subtypeName != "Link" {
                smallButton(String(localized: "Küçült"), "minus.magnifyingglass") { session.scaleSelected(0.85) }
                smallButton(String(localized: "Büyüt"), "plus.magnifyingglass") { session.scaleSelected(1.18) }
            }
            smallButton(String(localized: "Sil"), "trash") { session.deleteSelected() }
        }
        .padding(4)
        .qGlassCapsule()
        .shadow(color: .black.opacity(0.10), radius: 6, x: 0, y: 3)
    }

    private var redactBar: some View {
        Button { session.applyRedactions() } label: {
            Label("Sansürü uygula (\(session.redactionMarkCount))", systemImage: "checkmark.seal")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.white)
                .padding(.horizontal, 18)
                .frame(minHeight: 44)
                .background(Theme.red, in: Capsule())
        }
    }

    private func smallButton(_ title: String, _ icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .labelStyle(.titleAndIcon)
                .font(.footnote)
                .foregroundStyle(Theme.text)
                .padding(.horizontal, 10)
                .frame(minHeight: 44)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Alt sekmeler

    private var bottomTabs: some View {
        HStack(spacing: 3) {
            ForEach(ViewerTab.allCases) { tab in
                let active = isActive(tab)
                Button { open(tab) } label: {
                    VStack(spacing: 2) {
                        Image(systemName: tab.icon).font(.system(size: 16, weight: .medium))
                            .frame(height: 20)
                        Text(tab == .allTools ? String(localized: "Araçlar") : tab.title)
                            .font(.caption2.weight(.medium))
                            .lineLimit(1)
                    }
                    .foregroundStyle(active ? Color(hex: 0x121A21) : Color.white)
                    .padding(.horizontal, 12)
                    .frame(minWidth: 64, minHeight: 48)
                    .background(active ? Color.white : Color.white.opacity(0.07), in: Capsule())
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(tab.title)
                .accessibilityAddTraits(active ? .isSelected : [])
            }
        }
        .padding(4)
        .background(Theme.pill, in: Capsule())
        .shadow(color: .black.opacity(0.22), radius: 10, x: 0, y: 6)
        .frame(maxWidth: .infinity)
        .padding(.top, 8)
        .padding(.bottom, 6)
        .background(Theme.viewerBackground.ignoresSafeArea(edges: .bottom))
    }

    private func isActive(_ tab: ViewerTab) -> Bool {
        session.activeTab == tab || session.mode == tab
    }

    private func open(_ tab: ViewerTab) {
        session.commitInlineIfNeeded()
        switch tab {
        case .edit:
            if session.mode != .edit { session.enterMode(.edit) }
            detent = .height(220)
        case .sign:
            if session.mode != .sign { session.enterMode(.sign) }
            detent = .medium
        default:
            detent = .medium
        }
        session.activeTab = tab
    }
}
