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
            List {
                Section {
                    row("Kaydet", "square.and.arrow.down", Theme.blue) {
                        if session.save() { session.infoMessage = "Kaydedildi." }
                    }
                    row("Paylaş / kopyasını kaydet", "square.and.arrow.up", Theme.blue) { share() }
                    row("Yazdır", "printer", Theme.secondary) { printDocument() }
                    row(library.isStarred(session.url) ? "Yıldızı kaldır" : "Yıldızla", "star", Theme.star) {
                        if let u = session.url { library.toggleStar(u) }
                    }
                }
                Section("Düzenle ve organize et") {
                    row("Sayfaları organize et", "square.grid.2x2", Theme.leaf) { session.openOrganizer() }
                    row("Dosyaları birleştir", "rectangle.stack.badge.plus", Theme.blue) { showMergeImporter = true }
                    row("Boş sayfa ekle", "doc.badge.plus", Theme.accent) { session.insertBlankPage(after: session.currentPageIndex) }
                    link("PDF Böl", "scissors", Theme.purple) {
                        PanelPage(title: "PDF Böl") {
                            SessionDataView(session: session) { d in SplitForm(data: d, name: session.displayName) }
                        }
                    }
                    link("Üstbilgi ve altbilgi", "rectangle.topthird.inset.filled", Theme.secondary) { HeaderFooterForm(session: session) }
                    link("Filigran", "drop", Theme.secondary) { WatermarkForm(session: session) }
                }
                Section("Koruma ve gizlilik") {
                    link("PDF Sıkıştır", "arrow.down.right.and.arrow.up.left", Theme.accent) {
                        PanelPage(title: "PDF Sıkıştır") {
                            SessionDataView(session: session) { d in CompressForm(data: d, name: session.displayName) }
                        }
                    }
                    link("Şifreyle Koru", "lock.shield", Theme.indigo) {
                        PanelPage(title: "Şifreyle Koru") {
                            SessionDataView(session: session) { d in ProtectForm(data: d, name: session.displayName) }
                        }
                    }
                    row("PDF'de Sansürle", "eye.slash", Theme.pink) {
                        session.tool = .redact
                        detent = .height(220)
                    }
                    if session.redactionMarkCount > 0 {
                        row("Sansürü uygula (\(session.redactionMarkCount) alan)", "checkmark.seal", Theme.pink) { confirmRedact = true }
                    }
                    link("Hassas bilgileri kaldır", "hand.raised", Theme.secondary) {
                        PanelPage(title: "Hassas bilgileri kaldır") {
                            SessionDataView(session: session) { d in SanitizeForm(data: d, name: session.displayName) }
                        }
                    }
                }
                Section("Tanıma ve yorum") {
                    row("Tara ve OCR (aranabilir metin)", "text.viewfinder", Theme.blue) {
                        close()
                        session.runOCR(force: false)
                    }
                    row("Yorum ekle", "text.bubble", Theme.orange) {
                        session.tool = .comment
                        detent = .height(220)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(Theme.background)
            .navigationTitle("Tüm araçlar")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: close) { Image(systemName: "xmark").font(.system(size: 15, weight: .semibold)) }
                        .accessibilityLabel("Kapat")
                }
            }
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

    private func row(_ title: String, _ icon: String, _ tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon).font(.system(size: 17)).foregroundStyle(tint).frame(width: 24)
                Text(title).font(.system(size: 15.5)).foregroundStyle(Theme.text)
            }
        }
        .listRowBackground(Theme.card)
    }

    private func link<D: View>(_ title: String, _ icon: String, _ tint: Color, @ViewBuilder destination: @escaping () -> D) -> some View {
        NavigationLink {
            destination()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: icon).font(.system(size: 17)).foregroundStyle(tint).frame(width: 24)
                Text(title).font(.system(size: 15.5)).foregroundStyle(Theme.text)
            }
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
