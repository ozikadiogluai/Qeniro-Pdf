import SwiftUI
import UniformTypeIdentifiers

/// Görüntüleyicideki "Tüm araçlar" paneli.
struct AllToolsPanel: View {
    @ObservedObject var session: DocumentSession
    @EnvironmentObject private var library: FileLibrary
    @Binding var detent: PresentationDetent
    var share: () -> Void
    var close: () -> Void
    @State private var showMergeImporter = false
    @State private var confirmRedact = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
            SheetHeader(title: String(localized: "Tüm araçlar"), cancelTitle: String(localized: "Kapat"), onCancel: close)
                .padding(.horizontal, 12)
                .padding(.top, 14)
                .padding(.bottom, 4)
            List {
                Section {
                    row(String(localized: "Kaydet"), "square.and.arrow.down", Theme.blue) {
                        if session.save() { session.infoMessage = "Kaydedildi." }
                    }
                    row(String(localized: "Paylaş / kopyasını kaydet"), "square.and.arrow.up", Theme.blue) { share() }
                    row(String(localized: "Yazdır"), "printer", Theme.secondary) { printDocument() }
                    row(library.isStarred(session.url) ? String(localized: "Yıldızı kaldır") : String(localized: "Yıldızla"), "star", Theme.star) {
                        if let u = session.url { library.toggleStar(u) }
                    }
                }
                Section("Düzenle ve organize et") {
                    row(String(localized: "Sayfaları organize et"), "square.grid.2x2", Theme.leaf) { session.openOrganizer() }
                    row(String(localized: "Dosyaları birleştir"), "rectangle.stack.badge.plus", Theme.blue) { showMergeImporter = true }
                    row(String(localized: "Boş sayfa ekle"), "doc.badge.plus", Theme.accent) { session.insertBlankPage(after: session.currentPageIndex) }
                    link(String(localized: "PDF Böl"), "scissors", Theme.purple) {
                        PanelPage(title: String(localized: "PDF Böl")) {
                            SessionDataView(session: session) { d in SplitForm(data: d, name: session.displayName) }
                        }
                    }
                    link(String(localized: "Üstbilgi ve altbilgi"), "rectangle.topthird.inset.filled", Theme.secondary) { HeaderFooterForm(session: session) }
                    link(String(localized: "Filigran"), "drop", Theme.secondary) { WatermarkForm(session: session) }
                }
                Section("Koruma ve gizlilik") {
                    link(String(localized: "PDF Sıkıştır"), "arrow.down.right.and.arrow.up.left", Theme.accent) {
                        PanelPage(title: String(localized: "PDF Sıkıştır")) {
                            SessionDataView(session: session) { d in CompressForm(data: d, name: session.displayName) }
                        }
                    }
                    link(String(localized: "Şifreyle Koru"), "lock.shield", Theme.indigo) {
                        PanelPage(title: String(localized: "Şifreyle Koru")) {
                            SessionDataView(session: session) { d in ProtectForm(data: d, name: session.displayName) }
                        }
                    }
                    row(String(localized: "PDF'de Sansürle"), "eye.slash", Theme.pink) {
                        session.tool = .redact
                        detent = .height(220)
                    }
                    if session.redactionMarkCount > 0 {
                        row(String(localized: "Sansürü uygula (\(session.redactionMarkCount) alan)"), "checkmark.seal", Theme.pink) { confirmRedact = true }
                    }
                    link(String(localized: "Hassas bilgileri kaldır"), "hand.raised", Theme.secondary) {
                        PanelPage(title: String(localized: "Hassas bilgileri kaldır")) {
                            SessionDataView(session: session) { d in SanitizeForm(data: d, name: session.displayName) }
                        }
                    }
                }
                Section("Tanıma ve yorum") {
                    row(String(localized: "Tara ve OCR (aranabilir metin)"), "text.viewfinder", Theme.blue) {
                        close()
                        session.runOCR(force: false)
                    }
                    row(String(localized: "Yorum ekle"), "text.bubble", Theme.orange) {
                        session.tool = .comment
                        detent = .height(220)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .listSectionSpacing(.compact)
            }
            .background(Theme.background)
            .toolbar(.hidden, for: .navigationBar)
        }
        .fileImporter(isPresented: $showMergeImporter, allowedContentTypes: [.pdf], allowsMultipleSelection: true) { result in
            if case .success(let urls) = result, !urls.isEmpty { session.appendPDFs(urls) }
        }
        .confirmationDialog("İşaretli alanlar kalıcı olarak kaldırılsın mı?", isPresented: $confirmRedact, titleVisibility: .visible) {
            Button("Sansürü uygula", role: .destructive) { session.applyRedactions() }
            Button("Vazgeç", role: .cancel) {}
        } message: {
            Text("Bu sayfalar görüntüye çevrilir; işaretli alanların altındaki metin ve görüntüler silinir. Diğer metin OCR ile aranabilir kalır.")
        }
    }

    private func rowLabel(_ title: String, _ icon: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundStyle(Theme.ink)
                .frame(width: 34, height: 34)
                .background(Theme.card2, in: Circle())
            Text(title).font(.subheadline).foregroundStyle(Theme.text)
        }
        .frame(minHeight: 44)
    }

    private func row(_ title: String, _ icon: String, _ tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            rowLabel(title, icon)
        }
        .listRowBackground(Theme.card)
    }

    private func link<D: View>(_ title: String, _ icon: String, _ tint: Color, @ViewBuilder destination: @escaping () -> D) -> some View {
        NavigationLink {
            destination()
        } label: {
            rowLabel(title, icon)
        }
        .listRowBackground(Theme.card)
    }

    private func printDocument() {
        guard let data = session.currentData() else { return }
        let pc = UIPrintInteractionController.shared
        let info = UIPrintInfo(dictionary: nil)
        info.outputType = .general
        info.jobName = session.displayName
        pc.printInfo = info
        pc.printingItem = data
        // Panel kapandıktan sonra sun (aynı anda tek sayfa sunulabilir).
        close()
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 450_000_000)
            pc.present(animated: true, completionHandler: nil)
        }
    }
}
