import SwiftUI
import AppKit
import PDFKit

struct PDFKitView: NSViewRepresentable {
    let session: DocumentSession

    func makeNSView(context: Context) -> QPDFView {
        let v = session.pdfView
        v.removeFromSuperview()
        return v
    }

    func updateNSView(_ nsView: QPDFView, context: Context) {}
}

struct ThumbnailsView: NSViewRepresentable {
    let session: DocumentSession

    func makeNSView(context: Context) -> PDFThumbnailView {
        let v = session.thumbnailView
        v.removeFromSuperview()
        return v
    }

    func updateNSView(_ nsView: PDFThumbnailView, context: Context) {}
}

/// Açık belge: üstte sekmeler (Tüm araçlar · Düzenle · Dönüştür · E-imza), solda araç paneli,
/// sayfa alanının solunda yüzen hızlı araç çubuğu.
struct ViewerView: View {
    @EnvironmentObject var app: AppState
    @ObservedObject var session: DocumentSession

    var body: some View {
        VStack(spacing: 0) {
            ViewerTabsBar(session: session)
            Divider()
            ViewerToolbar(session: session)
            Divider()
            if session.isSearching {
                SearchBar(session: session)
                Divider()
            }
            if let hint = session.tool.hint {
                HStack(spacing: 8) {
                    Image(systemName: "info.circle")
                    Text(hint)
                        .lineLimit(2)
                    Spacer()
                    Button("Vazgeç") { session.tool = .select }
                        .buttonStyle(.link)
                }
                .font(.callout)
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background(Theme.activeNav)
                Divider()
            }
            if let notice = session.editNotice {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Theme.orange)
                    Text(notice)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer()
                    Button { session.editNotice = nil } label: { Image(systemName: "xmark") }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                }
                .font(.callout)
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background(Theme.noticeBackground)
                Divider()
            }
            HStack(spacing: 0) {
                if let panel = session.panel, !session.showOrganizer {
                    ToolPanelHost(session: session, panel: panel)
                        .frame(width: Theme.toolPanelWidth)
                        .background(Theme.window)
                    Divider()
                }
                if session.showThumbnails && !session.showOrganizer {
                    ThumbnailsView(session: session)
                        .frame(width: 130)
                    Divider()
                }
                VStack(spacing: 0) {
                    if session.signatureProblem && !session.showOrganizer {
                        SignatureProblemBanner(session: session)
                    }
                    ZStack(alignment: .topLeading) {
                        if session.showOrganizer {
                            PageOrganizerView(session: session)
                        } else {
                            PDFKitView(session: session)
                            QuickToolRail(session: session)
                                .padding(.leading, 14)
                                .padding(.top, 14)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .overlay {
                        if let msg = session.busyMessage {
                            VStack(spacing: 10) {
                                ProgressView()
                                Text(msg).font(.callout)
                            }
                            .padding(22)
                            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle(session.displayName + (session.isDirty ? " — Düzenlendi" : "") + " — Qeniro PDF")
        .onDisappear { session.tool = .select }
    }
}

/// Üstteki dört sekme.
struct ViewerTabsBar: View {
    @ObservedObject var session: DocumentSession

    var body: some View {
        HStack(spacing: 2) {
            ForEach(ViewerTab.allCases) { tab in
                let active = session.viewerTab == tab
                Button {
                    if session.showOrganizer { session.showOrganizer = false }
                    if active && session.panel == .tab {
                        session.panel = nil
                    } else {
                        session.viewerTab = tab
                        session.panel = .tab
                    }
                } label: {
                    VStack(spacing: 6) {
                        Text(tab.title)
                            .font(.system(size: 14, weight: active ? .semibold : .regular))
                            .foregroundStyle(Color.primary)
                            .padding(.horizontal, 12)
                            .padding(.top, 9)
                        Rectangle()
                            .fill(active ? Color.primary : Color.clear)
                            .frame(height: 3)
                    }
                    .fixedSize()
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            Spacer()
            Button {
                session.panel = session.panel == nil ? .tab : nil
            } label: {
                Image(systemName: "sidebar.left")
                    .foregroundStyle(session.panel != nil ? Theme.selection : Color.primary)
            }
            .buttonStyle(.plain)
            .help(session.panel == nil ? "Araç panelini göster" : "Araç panelini gizle")
            .padding(.trailing, 12)
        }
        .padding(.leading, 10)
        .background(Theme.window)
    }
}

/// Sol paneldeki içerik seçici.
struct ToolPanelHost: View {
    @ObservedObject var session: DocumentSession
    let panel: SidePanel

    var body: some View {
        switch panel {
        case .tab:
            switch session.viewerTab {
            case .allTools: AllToolsPanel(session: session)
            case .edit: EditTabPanel(session: session)
            case .convert: ConvertTabPanel(session: session)
            case .sign: SignTabPanel(session: session)
            }
        case .redact: RedactPanel(session: session)
        case .headerFooter: HeaderFooterPanel(session: session)
        case .watermark: WatermarkPanel(session: session)
        case .formPrepare: FormPreparePanel(session: session)
        case .verifySignatures: VerifySignaturesPanel(session: session)
        }
    }
}

/// "En az bir imzada sorun var." bandı (yalnızca belgede gerçekten imza varsa).
struct SignatureProblemBanner: View {
    @ObservedObject var session: DocumentSession

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Color(nsColor: Theme.hex(0xE8A10A)))
                .font(.system(size: 16))
            Text("En az bir imzada sorun var.")
                .font(.system(size: 14))
            Spacer()
            Button("İmza panelini aç") {
                session.viewerTab = .sign
                session.panel = .verifySignatures
            }
            .buttonStyle(.link)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 11)
        .background(Theme.signatureBanner)
    }
}

struct SearchBar: View {
    @ObservedObject var session: DocumentSession
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Belgede ara", text: $session.searchText)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 280)
                .focused($focused)
                .onSubmit { session.search() }
            if !session.searchResults.isEmpty {
                Text("\(session.searchIndex + 1) / \(session.searchResults.count)")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            } else if !session.searchText.isEmpty {
                Text("Enter ile ara").foregroundStyle(.secondary).font(.caption)
            }
            Button { session.previousResult() } label: { Image(systemName: "chevron.up") }
                .disabled(session.searchResults.isEmpty)
                .help("Önceki sonuç")
            Button { session.nextResult() } label: { Image(systemName: "chevron.down") }
                .disabled(session.searchResults.isEmpty)
                .help("Sonraki sonuç")
            Spacer()
            Button("Kapat") {
                session.clearSearch()
                session.isSearching = false
            }
            .keyboardShortcut(.cancelAction)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .onAppear { focused = true }
    }
}
