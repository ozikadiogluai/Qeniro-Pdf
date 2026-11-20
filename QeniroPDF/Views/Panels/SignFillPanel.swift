import SwiftUI
import AppKit
import PDFKit

/// "E-imza" sekmesi: kendin doldur ve imzala, imza iste (imza alanı), sertifika, doğrulama.
struct SignTabPanel: View {
    @EnvironmentObject var app: AppState
    @EnvironmentObject var signatures: SignatureStore
    @ObservedObject var session: DocumentSession
    @State private var showCreator = false
    @State private var creatorText: String?
    @FocusState private var contentFocused: Bool

    private var selectedFreeText: PDFAnnotation? {
        guard let a = session.selectedAnnotation, a.isFreeText else { return nil }
        return a
    }

    static func userInitials() -> String {
        let name = NSFullUserName().isEmpty ? NSUserName() : NSFullUserName()
        let letters = name.split(separator: " ").compactMap { $0.first }.map { String($0).uppercased(with: Locale(identifier: "tr_TR")) }
        return letters.isEmpty ? "AB" : letters.joined(separator: ".") + "."
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                ToolPanelHeader(title: "E-imza", onClose: { session.panel = nil; session.tool = .select })

                PanelCard(title: "Kendin doldur ve imzala", spacing: 2, padding: 8) {
                if !signatures.signatures.isEmpty {
                    VStack(spacing: 6) {
                        ForEach(signatures.signatures) { sig in
                            signatureButton(sig)
                        }
                    }
                    .padding(.horizontal, 6)
                    .padding(.bottom, 4)
                }
                ToolListRow(symbol: "signature", title: "İmza ekle") {
                    if let first = signatures.signatures.first {
                        session.tool = .addSignature(first.id)
                    } else {
                        creatorText = nil
                        showCreator = true
                    }
                }
                ToolListRow(symbol: "plus", title: "Yeni imza oluştur") {
                    creatorText = nil
                    showCreator = true
                }
                ToolListRow(symbol: "textformat.abc", title: "Baş harfleri ekle") {
                    creatorText = Self.userInitials()
                    showCreator = true
                }
                ToolListRow(symbol: "textformat", title: "Metin ekle", active: session.tool == .addFillText) { session.tool = .addFillText }
                ToolListRow(symbol: "checkmark.square", title: "Onay kutusu", active: session.tool == .addCheckbox) { session.tool = .addCheckbox }
                ToolListRow(symbol: "smallcircle.filled.circle", title: "Radyo düğmesi", active: session.tool == .addRadio) { session.tool = .addRadio }
                ToolListRow(symbol: "calendar", title: "Tarih ekle", active: session.tool == .addDate) { session.tool = .addDate }

                if let a = selectedFreeText {
                    Text("Metin").font(.caption).foregroundStyle(.secondary).padding(.horizontal, 8).padding(.top, 6)
                    TextEditor(text: Binding(get: { a.contents ?? "" },
                                             set: { session.setContents($0, of: a) }))
                        .font(.system(size: 12))
                        .frame(height: 70)
                        .focused($contentFocused)
                        .scrollContentBackground(.hidden)
                        .padding(4)
                        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.card2))
                }

                Text("Öğeleri sürükleyerek taşıyın, köşelerden boyutlandırın, ⌫ ile silin. Bitirince **Uygula** ile sayfaya kalıcı olarak gömün.")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 8)
                    .padding(.top, 8)
                HStack {
                    if session.selectedAnnotation != nil {
                        Button(role: .destructive) { session.deleteSelected() } label: {
                            Label("Seçili öğeyi sil", systemImage: "trash")
                        }
                        .buttonStyle(QSecondaryButtonStyle(foreground: Theme.red))
                    }
                    Spacer()
                    Button("Uygula") { session.applyAnnotations() }
                        .buttonStyle(QSecondaryButtonStyle(filled: Theme.card2))
                        .help("Eklenen imza, metin ve form öğelerini sayfaya kalıcı olarak göm")
                }
                .padding(.horizontal, 8)
                .padding(.top, 6)

                }
                PanelCard(title: "E-imza iste", spacing: 2, padding: 8) {
                ToolListRow(symbol: "rectangle.and.pencil.and.ellipsis", title: "İmza alanı ekle", active: session.tool == .addSignatureField) {
                    session.tool = .addSignatureField
                }
                Text("Karşı tarafın imzalayacağı boş bir imza alanı ekler. Belgeyi kaydedip paylaşın.")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 8)

                }
                PanelCard(title: "Sertifika", spacing: 2, padding: 8) {
                ToolListRow(symbol: "checkmark.seal", title: "Sertifika ile İmzala") { app.perform(.certificateSign) }
                ToolListRow(symbol: "checkmark.shield", title: "İmzaları doğrula",
                            trailing: session.signatureInfos.isEmpty ? nil : "\(session.signatureInfos.count)") {
                    session.panel = .verifySignatures
                }
                }
            }
            .padding(12)
        }
        .onChange(of: session.focusTextRequest) { _, _ in
            Task { @MainActor in contentFocused = true }
        }
        .sheet(isPresented: $showCreator) {
            SignatureCreatorView(initialText: creatorText) { image in
                if let sig = signatures.add(image) {
                    session.tool = .addSignature(sig.id)
                }
            }
        }
    }

    @ViewBuilder
    private func signatureButton(_ sig: SavedSignature) -> some View {
        let active = session.tool == .addSignature(sig.id)
        Button {
            session.tool = .addSignature(sig.id)
        } label: {
            Group {
                if let img = signatures.image(for: sig.id) {
                    Image(nsImage: img).resizable().scaledToFit()
                } else {
                    Text("İmza").foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .padding(6)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.white))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(active ? Theme.hexColor(0x121A21) : Theme.divider, lineWidth: active ? 1.5 : 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("İmzayı yerleştirmek için tıklayın, sonra sayfada bir yere tıklayın")
        .contextMenu {
            Button("İmzayı Sil", role: .destructive) { signatures.delete(sig.id) }
        }
    }
}

/// "İmzaları doğrula" paneli.
struct VerifySignaturesPanel: View {
    @ObservedObject var session: DocumentSession

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                ToolPanelHeader(title: "İmzaları doğrula",
                                onBack: { session.panel = .tab },
                                onClose: { session.panel = nil })
                PanelCard(spacing: 10) {
                if !session.signaturesChecked {
                    ProgressView("Denetleniyor…")
                } else if session.signatureInfos.isEmpty {
                    Label("Bu belgede dijital imza yok.", systemImage: "seal")
                        .font(.callout)
                    if session.url == nil {
                        Text("Belge henüz bir dosyaya kaydedilmedi.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                } else {
                    let problems = session.signatureInfos.filter { $0.status != .valid }.count
                    Text(problems == 0 ? "Tüm imzalar geçerli." : "\(session.signatureInfos.count) imzadan \(problems) tanesinde sorun var.")
                        .font(.callout.weight(.semibold))
                    ForEach(session.signatureInfos) { info in
                        signatureCard(info)
                    }
                }
                if session.isDirty && !session.signatureInfos.isEmpty {
                    Text("Not: Kaydedilmemiş değişiklikler doğrulamaya dahil değildir. İmzalı bir belgeyi değiştirip kaydetmek mevcut imzaları geçersiz kılar.")
                        .font(.caption).foregroundStyle(Theme.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Button {
                    session.refreshSignatures()
                } label: {
                    Label("Yeniden doğrula", systemImage: "arrow.clockwise")
                }
                Text("Doğrulama, imzanın kapsadığı baytları ve imzalayan sertifikasını macOS güven ayarlarına göre denetler.")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(12)
        }
    }

    private func signatureCard(_ info: PDFSignatureInfo) -> some View {
        let symbol: String
        let color: Color
        switch info.status {
        case .valid:
            symbol = "checkmark.seal.fill"; color = Theme.green
        case .invalid:
            symbol = "xmark.seal.fill"; color = Theme.accent
        case .unknown:
            symbol = "questionmark.circle.fill"; color = Theme.orange
        }
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Image(systemName: symbol).foregroundStyle(color).font(.system(size: 18))
                Text(info.signer.isEmpty ? "İmza \(info.id + 1)" : info.signer)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(2)
            }
            if !info.time.isEmpty {
                Text("Tarih: \(info.time)").font(.caption).foregroundStyle(.secondary)
            }
            if !info.reason.isEmpty {
                Text("Neden: \(info.reason)").font(.caption).foregroundStyle(.secondary)
            }
            if !info.subFilter.isEmpty {
                Text("Biçim: \(info.subFilter)").font(.caption2).foregroundStyle(.secondary)
            }
            Text(info.detail)
                .font(.caption)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.card2))
    }
}
