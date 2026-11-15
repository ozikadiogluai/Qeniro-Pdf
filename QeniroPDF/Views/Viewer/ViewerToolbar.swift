import SwiftUI
import AppKit

/// Ekran görüntüsündeki belge araç çubuğu: Kaydet, Yıldızla, Yazdır, Ara | Seçim, sayfa, El, Zoom, Döndür | Uygula.
struct ViewerToolbar: View {
    @EnvironmentObject var app: AppState
    @EnvironmentObject var library: FileLibrary
    @ObservedObject var session: DocumentSession
    @State private var pageText = "1"

    var body: some View {
        HStack(spacing: 4) {
            iconButton("square.and.arrow.down", "Kaydet (⌘S)") { _ = session.save() }
            iconButton(library.isStarred(session.url) ? "star.fill" : "star",
                       library.isStarred(session.url) ? "Yıldızı kaldır" : "Yıldızla",
                       tint: library.isStarred(session.url) ? .yellow : nil) {
                if let u = session.url { library.toggleStar(u) } else {
                    Dialogs.info("Önce kaydedin", "Yıldızlamak için belgeyi önce bir dosyaya kaydedin.")
                }
            }
            iconButton("printer", "Yazdır (⌘P)") { session.printDocument() }
            iconButton("magnifyingglass", "Ara (⌘F)", active: session.isSearching) { session.isSearching.toggle() }

            separator

            iconButton("cursorarrow", "Seçim aracı", active: session.tool == .select) { session.tool = .select }
            HStack(spacing: 4) {
                TextField("", text: $pageText)
                    .frame(width: 38)
                    .multilineTextAlignment(.center)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit {
                        if let n = Int(pageText) { session.goTo(page: n - 1) }
                        pageText = "\(session.currentPageIndex + 1)"
                    }
                Text("/ \(session.pageCount)")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 4)
            iconButton("chevron.up", "Önceki sayfa") { session.previousPage() }
                .disabled(session.currentPageIndex == 0)
            iconButton("chevron.down", "Sonraki sayfa") { session.nextPage() }
                .disabled(session.currentPageIndex >= session.pageCount - 1)
            iconButton("hand.raised", "El aracı", active: session.tool == .hand) { session.tool = .hand }
            iconButton("minus.magnifyingglass", "Uzaklaştır (⌘−)") { session.zoomOut() }
            Menu {
                ForEach([0.5, 0.75, 1.0, 1.25, 1.5, 2.0, 3.0, 4.0], id: \.self) { z in
                    Button(Fmt.percent(CGFloat(z))) { session.setZoom(CGFloat(z)) }
                }
                Divider()
                Button("Sayfaya sığdır") { session.fitPage() }
                Button("Genişliğe sığdır") { session.fitWidth() }
            } label: {
                Text(Fmt.percent(session.scaleFactor)).monospacedDigit()
            }
            .menuStyle(.button)
            .buttonStyle(.bordered)
            .fixedSize()
            iconButton("plus.magnifyingglass", "Yakınlaştır (⌘+)") { session.zoomIn() }
            Menu {
                Button("Sağa döndür (90°)") { session.rotateCurrent(by: 90) }
                Button("Sola döndür (90°)") { session.rotateCurrent(by: -90) }
                Button("Tüm sayfaları sağa döndür") { session.rotate(pages: Array(0..<session.pageCount), by: 90) }
            } label: {
                Image(systemName: "rotate.right")
            }
            .menuStyle(.button)
            .buttonStyle(.borderless)
            .fixedSize()
            .help("Döndür")

            separator

            iconButton("sidebar.left", "Sayfa küçük resimleri", active: session.showThumbnails) { session.showThumbnails.toggle() }
            iconButton("arrow.uturn.backward", "Geri al (⌘Z)") { app.undo() }
            iconButton("arrow.uturn.forward", "Yinele (⇧⌘Z)") { app.redo() }

            Spacer()

            Menu {
                Button("PDF Düzenle") { app.perform(.edit) }
                Button("İmzala ve Doldur") { app.perform(.signFill) }
                Button("PDF Sayfaları Düzenle") { app.perform(.organize) }
                Button("PDF'de Sansürle") { app.perform(.redact) }
                Divider()
                Button("Metin tanıma (OCR) – taranmış sayfalar") { session.runOCR(force: false) }
                Button("Metin tanıma (OCR) – tüm sayfalar") { session.runOCR(force: true) }
                Divider()
                ForEach([ToolKind.compress, .protect, .convert, .split, .merge, .certificateSign, .sanitize]) { t in
                    Button(t.title) { app.perform(t) }
                }
            } label: {
                Label("Araçlar", systemImage: "square.grid.2x2")
            }
            .menuStyle(.button)
            .buttonStyle(.bordered)
            .fixedSize()

            if session.showOrganizer {
                Button("Bitti") { session.showOrganizer = false }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.selection)
            }
            if session.viewerTab == .sign && session.panel == .tab && !session.showOrganizer {
                Button("Uygula") { session.applyAnnotations() }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.applyPurple)
                    .help("Eklenen imza, metin ve form öğelerini sayfaya kalıcı olarak göm")
            }
            if session.panel == .redact && !session.showOrganizer {
                Button("Sansürü Uygula") { session.applyRedactions(restoreText: true) }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.accent)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Theme.window)
        .onAppear { pageText = "\(session.currentPageIndex + 1)" }
        .onChange(of: session.currentPageIndex) { _, new in pageText = "\(new + 1)" }
    }

    private var separator: some View {
        Divider().frame(height: 20).padding(.horizontal, 6)
    }

    private func iconButton(_ symbol: String, _ help: String, active: Bool = false, tint: Color? = nil, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 14))
                .foregroundStyle(tint ?? (active ? Theme.selection : Color.primary))
                .frame(width: 28, height: 26)
                .background(RoundedRectangle(cornerRadius: 6).fill(active ? Theme.activeNav : Color.clear))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
    }
}
