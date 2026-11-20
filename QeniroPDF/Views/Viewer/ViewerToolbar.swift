import SwiftUI
import AppKit

/// Görüntüleyicinin üst cam araç çubuğu: geri, dosya adı, ortada sekme kapsülü
/// (Tüm araçlar · Düzenle · Dönüştür · E-imza), sağda geri al / ara / yazdır / paylaş / diğer ve koyu birincil eylem.
struct ViewerToolbar: View {
    @EnvironmentObject var app: AppState
    @EnvironmentObject var library: FileLibrary
    @ObservedObject var session: DocumentSession

    var body: some View {
        HStack(spacing: 10) {
            Button { app.showShell(.home) } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.text)
                    .frame(width: 32, height: 32)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .qGlass(Circle())
            .help("Ana sayfaya dön (belge açık kalır)")
            .accessibilityLabel("Geri")

            VStack(alignment: .leading, spacing: 1) {
                Text(session.displayName)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text("Sayfa \(session.currentPageIndex + 1) / \(session.pageCount)" + (session.isDirty ? " · Düzenlendi" : ""))
                    .font(.subheadline)
                    .monospacedDigit()
                    .foregroundStyle(Theme.secondaryText)
                    .lineLimit(1)
            }
            .frame(width: 200, alignment: .leading)

            Spacer(minLength: 8)
            tabSegment
            Spacer(minLength: 8)

            HStack(spacing: 0) {
                glassIcon("sidebar.left", session.panel == nil ? "Araç panelini göster" : "Araç panelini gizle",
                          active: session.panel != nil) {
                    session.panel = session.panel == nil ? .tab : nil
                }
                glassIcon("arrow.uturn.backward", "Geri al (⌘Z)") { app.undo() }
                glassIcon("magnifyingglass", "Ara (⌘F)", active: session.isSearching) { session.isSearching.toggle() }
                glassIcon("printer", "Yazdır (⌘P)") { session.printDocument() }
                glassIcon("square.and.arrow.up", "Paylaş") { session.shareForReview() }
                moreMenu
            }
            .qGlassCapsule()

            primaryActions
        }
        .padding(.leading, 16)
        .padding(.trailing, 12)
        .frame(height: 56)
        .background(
            LinearGradient(stops: [.init(color: Theme.canvas.opacity(0.96), location: 0.7),
                                   .init(color: Theme.canvas.opacity(0), location: 1)],
                           startPoint: .top, endPoint: .bottom)
        )
    }

    // MARK: Sekme kapsülü

    private var tabSegment: some View {
        HStack(spacing: 2) {
            ForEach(ViewerTab.allCases) { tab in
                let active = session.viewerTab == tab && session.panel == .tab && !session.showOrganizer
                Button {
                    if session.showOrganizer { session.showOrganizer = false }
                    if active {
                        session.panel = nil
                    } else {
                        session.viewerTab = tab
                        session.panel = .tab
                    }
                } label: {
                    Text(tab.title)
                        .font(.body.weight(active ? .semibold : .regular))
                        .foregroundStyle(active ? Theme.onInk : Theme.text)
                        .padding(.horizontal, 14)
                        .frame(height: 30)
                        .background(Capsule().fill(active ? Theme.ink : Color.clear))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(active ? .isSelected : [])
            }
        }
        .padding(3)
        .qGlassCapsule()
        .fixedSize()
    }

    // MARK: Diğer menüsü

    private var moreMenu: some View {
        Menu {
            Button(library.isStarred(session.url) ? "Yıldızı kaldır" : "Yıldızla") {
                if let u = session.url { library.toggleStar(u) } else {
                    Dialogs.info("Önce kaydedin", "Yıldızlamak için belgeyi önce bir dosyaya kaydedin.")
                }
            }
            Button("Yinele (⇧⌘Z)") { app.redo() }
            Divider()
            Button("Seçim aracı") { session.tool = .select }
            Button("El aracı") { session.tool = .hand }
            Button(session.showThumbnails ? "Sayfa küçük resimlerini gizle" : "Sayfa küçük resimlerini göster") {
                session.showThumbnails.toggle()
            }
            Divider()
            Button("Sağa döndür (90°)") { session.rotateCurrent(by: 90) }
            Button("Sola döndür (90°)") { session.rotateCurrent(by: -90) }
            Button("Tüm sayfaları sağa döndür") { session.rotate(pages: Array(0..<session.pageCount), by: 90) }
            Divider()
            Menu("Araçlar") {
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
            }
            Button("Farklı kaydet…") { _ = session.saveAs() }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.text)
                .frame(width: 34, height: 32)
                .contentShape(Rectangle())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Diğer")
        .accessibilityLabel("Diğer seçenekler")
    }

    // MARK: Birincil eylem

    @ViewBuilder
    private var primaryActions: some View {
        if session.showOrganizer {
            Button("Bitti") { session.showOrganizer = false }
                .buttonStyle(QPrimaryButtonStyle())
        } else if session.viewerTab == .sign && session.panel == .tab {
            Button("Kaydet") { _ = session.save() }
                .buttonStyle(QSecondaryButtonStyle(filled: Theme.card))
            Button("Uygula") { session.applyAnnotations() }
                .buttonStyle(QPrimaryButtonStyle())
                .help("Eklenen imza, metin ve form öğelerini sayfaya kalıcı olarak göm")
        } else if session.panel == .redact {
            Button("Kaydet") { _ = session.save() }
                .buttonStyle(QSecondaryButtonStyle(filled: Theme.card))
            Button("Sansürü Uygula") { session.applyRedactions(restoreText: true) }
                .buttonStyle(QDestructiveButtonStyle())
        } else {
            Button("Kaydet") { _ = session.save() }
                .buttonStyle(QPrimaryButtonStyle())
                .help("Kaydet (⌘S)")
        }
    }

    private func glassIcon(_ symbol: String, _ help: String, active: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(active ? Theme.onInk : Theme.text)
                .frame(width: 30, height: 26)
                .background(Capsule().fill(active ? Theme.ink : Color.clear))
                .frame(width: 34, height: 32)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(help)
    }
}

/// Sayfa alanının altında yüzen cam kapsül: sayfa gezinme ve yakınlaştırma.
struct PageZoomCapsule: View {
    @ObservedObject var session: DocumentSession
    @State private var pageText = "1"

    var body: some View {
        HStack(spacing: 2) {
            capsuleIcon("chevron.up", "Önceki sayfa") { session.previousPage() }
                .disabled(session.currentPageIndex == 0)
            TextField("", text: $pageText)
                .textFieldStyle(.plain)
                .multilineTextAlignment(.center)
                .monospacedDigit()
                .frame(width: 30)
                .accessibilityLabel("Sayfa numarası")
                .onSubmit {
                    if let n = Int(pageText) { session.goTo(page: n - 1) }
                    pageText = "\(session.currentPageIndex + 1)"
                }
            Text("/ \(session.pageCount)")
                .monospacedDigit()
                .foregroundStyle(Theme.secondaryText)
            capsuleIcon("chevron.down", "Sonraki sayfa") { session.nextPage() }
                .disabled(session.currentPageIndex >= session.pageCount - 1)
            Rectangle().fill(Theme.divider).frame(width: 1, height: 16).padding(.horizontal, 4)
            capsuleIcon("minus", "Uzaklaştır (⌘−)") { session.zoomOut() }
            Menu {
                ForEach([0.5, 0.75, 1.0, 1.25, 1.5, 2.0, 3.0, 4.0], id: \.self) { z in
                    Button(Fmt.percent(CGFloat(z))) { session.setZoom(CGFloat(z)) }
                }
                Divider()
                Button("Sayfaya sığdır") { session.fitPage() }
                Button("Genişliğe sığdır") { session.fitWidth() }
            } label: {
                Text(Fmt.percent(session.scaleFactor))
                    .monospacedDigit()
                    .foregroundStyle(Theme.text)
                    .frame(minWidth: 44)
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .fixedSize()
            .accessibilityLabel("Yakınlaştırma oranı")
            capsuleIcon("plus", "Yakınlaştır (⌘+)") { session.zoomIn() }
        }
        .font(.body)
        .padding(.horizontal, 6)
        .frame(height: 34)
        .qGlassCapsule()
        .onAppear { pageText = "\(session.currentPageIndex + 1)" }
        .onChange(of: session.currentPageIndex) { _, new in pageText = "\(new + 1)" }
    }

    private func capsuleIcon(_ symbol: String, _ help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.text)
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(help)
    }
}
