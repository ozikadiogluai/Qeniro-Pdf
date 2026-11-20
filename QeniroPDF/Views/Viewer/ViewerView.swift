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

/// Açık belge: üstte cam araç çubuğu (sekmeler ortada), solda 290 pt araç paneli (beyaz kartlar),
/// sayfa alanının solunda yüzen cam hızlı araç çubuğu, altta sayfa/yakınlaştırma kapsülü.
struct ViewerView: View {
    @EnvironmentObject var app: AppState
    @ObservedObject var session: DocumentSession
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            ViewerToolbar(session: session)
            if session.isSearching {
                SearchBar(session: session)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 6)
            }
            if let hint = session.tool.hint {
                banner(symbol: "info.circle", tint: Theme.navy) {
                    Text(hint).lineLimit(2)
                    Spacer()
                    Button("Vazgeç") { session.tool = .select }
                        .buttonStyle(QSecondaryButtonStyle(height: 26, filled: Theme.card2))
                }
            }
            if let notice = session.editNotice {
                banner(symbol: "exclamationmark.triangle.fill", tint: Theme.orange) {
                    Text(notice).fixedSize(horizontal: false, vertical: true)
                    Spacer()
                    Button { session.editNotice = nil } label: { Image(systemName: "xmark") }
                        .buttonStyle(.plain)
                        .foregroundStyle(Theme.secondaryText)
                        .accessibilityLabel("Uyarıyı kapat")
                }
            }
            HStack(spacing: 10) {
                if let panel = session.panel, !session.showOrganizer {
                    ToolPanelHost(session: session, panel: panel)
                        .frame(width: Theme.toolPanelWidth)
                        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Theme.background))
                        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                        .shadow(color: .black.opacity(0.05), radius: 1, y: 1)
                        .transition(reduceMotion ? AnyTransition.opacity : AnyTransition.move(edge: .leading).combined(with: AnyTransition.opacity))
                }
                if session.showThumbnails && !session.showOrganizer {
                    ThumbnailsView(session: session)
                        .frame(width: 130)
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
                VStack(spacing: 8) {
                    if session.signatureProblem && !session.showOrganizer {
                        SignatureProblemBanner(session: session)
                    }
                    ZStack(alignment: .topLeading) {
                        if session.showOrganizer {
                            PageOrganizerView(session: session)
                        } else {
                            PDFKitView(session: session)
                            QuickToolRail(session: session)
                                .padding(.leading, 16)
                                .padding(.top, 16)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .overlay(alignment: .bottom) {
                        if !session.showOrganizer {
                            PageZoomCapsule(session: session)
                                .padding(.bottom, 14)
                        }
                    }
                    .overlay {
                        if let msg = session.busyMessage {
                            VStack(spacing: 10) {
                                ProgressView()
                                Text(msg).font(.callout)
                            }
                            .padding(22)
                            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .padding(.leading, 10)
            .padding(.bottom, 10)
            .animation(reduceMotion ? nil : Animation.easeInOut(duration: 0.18), value: session.panel == nil)
        }
        .background(Theme.canvas)
        .navigationTitle(session.displayName + (session.isDirty ? " — Düzenlendi" : "") + " — Qeniro PDF")
        .onDisappear { session.tool = .select }
    }

    private func banner<Content: View>(symbol: String, tint: Color, @ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 8) {
            Image(systemName: symbol).foregroundStyle(tint).accessibilityHidden(true)
            content()
        }
        .font(.callout)
        .foregroundStyle(Theme.text)
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .background(Capsule().fill(Theme.card))
        .padding(.horizontal, 12)
        .padding(.bottom, 6)
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
                .foregroundStyle(Theme.orange)
                .font(.system(size: 15))
                .accessibilityHidden(true)
            Text("En az bir imzada sorun var.")
                .font(.body)
                .foregroundStyle(Theme.text)
            Spacer()
            Button("İmza panelini aç") {
                session.viewerTab = .sign
                session.panel = .verifySignatures
            }
            .buttonStyle(QSecondaryButtonStyle(height: 28, filled: Theme.card2))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Theme.card))
        .padding(.trailing, 10)
    }
}

struct SearchBar: View {
    @ObservedObject var session: DocumentSession
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundStyle(Theme.secondaryText).accessibilityHidden(true)
                TextField("Belgede ara", text: $session.searchText)
                    .textFieldStyle(.plain)
                    .focused($focused)
                    .onSubmit { session.search() }
            }
            .padding(.horizontal, 12)
            .frame(width: 280, height: 30)
            .background(Capsule().fill(Theme.card2))
            if !session.searchResults.isEmpty {
                Text("\(session.searchIndex + 1) / \(session.searchResults.count)")
                    .monospacedDigit()
                    .foregroundStyle(Theme.secondaryText)
            } else if !session.searchText.isEmpty {
                Text("Enter ile ara").foregroundStyle(Theme.secondaryText).font(.callout)
            }
            Button { session.previousResult() } label: { Image(systemName: "chevron.up") }
                .buttonStyle(.plain)
                .disabled(session.searchResults.isEmpty)
                .help("Önceki sonuç")
                .accessibilityLabel("Önceki sonuç")
            Button { session.nextResult() } label: { Image(systemName: "chevron.down") }
                .buttonStyle(.plain)
                .disabled(session.searchResults.isEmpty)
                .help("Sonraki sonuç")
                .accessibilityLabel("Sonraki sonuç")
            Spacer()
            Button("Kapat") {
                session.clearSearch()
                session.isSearching = false
            }
            .buttonStyle(QSecondaryButtonStyle(height: 28, filled: Theme.card2))
            .keyboardShortcut(.cancelAction)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Capsule().fill(Theme.card))
        .onAppear { focused = true }
    }
}
