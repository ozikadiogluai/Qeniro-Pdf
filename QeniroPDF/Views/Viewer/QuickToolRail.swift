import SwiftUI
import AppKit

/// Sayfa alanının solunda yüzen dikey araç çubuğu: Seç, Yorum, Vurgula, Çiz, Diğer.
struct QuickToolRail: View {
    @ObservedObject var session: DocumentSession

    private var isMoreActive: Bool {
        switch session.tool {
        case .markup(.underline), .markup(.strikeOut), .shape: return true
        default: return false
        }
    }

    var body: some View {
        VStack(spacing: 2) {
            railButton("cursorarrow", String(localized: "Seç"), active: session.tool == .select || session.tool == .editText) {
                session.tool = session.viewerTab == .edit ? .editText : .select
            }
            railButton("text.bubble", String(localized: "Yorum (yapışkan not)"), active: session.tool == .note) {
                session.tool = .note
            }
            railButton("highlighter", String(localized: "Vurgula: metni sürükleyerek seçin"), active: session.tool == .markup(.highlight)) {
                session.tool = .markup(.highlight)
            }
            railButton("scribble", String(localized: "Çiz (serbest çizim)"), active: session.tool == .ink) {
                session.tool = .ink
            }
            Menu {
                Button { session.tool = .markup(.underline) } label: { Label("Altını çiz", systemImage: "underline") }
                Button { session.tool = .markup(.strikeOut) } label: { Label("Üstünü çiz", systemImage: "strikethrough") }
                Divider()
                Button { session.tool = .shape(.rectangle) } label: { Label("Dikdörtgen", systemImage: "rectangle") }
                Button { session.tool = .shape(.ellipse) } label: { Label("Elips", systemImage: "circle") }
                Divider()
                Menu("Çizim rengi") {
                    colorItem(String(localized: "Kırmızı"), NSColor(srgbRed: 0.90, green: 0.20, blue: 0.18, alpha: 1))
                    colorItem(String(localized: "Mavi"), NSColor(srgbRed: 0.18, green: 0.42, blue: 0.89, alpha: 1))
                    colorItem(String(localized: "Yeşil"), NSColor(srgbRed: 0.12, green: 0.56, blue: 0.24, alpha: 1))
                    colorItem(String(localized: "Siyah"), NSColor.black)
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 14, weight: .semibold))
                    .frame(width: 36, height: 36)
                    .foregroundStyle(isMoreActive ? Theme.onInk : Theme.text)
                    .background(Circle().fill(isMoreActive ? Theme.ink : Color.clear))
                    .contentShape(Circle())
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Diğer: altını çiz, üstünü çiz, şekil")
            .accessibilityLabel("Diğer araçlar")
        }
        .padding(4)
        .qGlassCapsule()
        .shadow(color: .black.opacity(0.12), radius: 10, y: 6)
    }

    private func colorItem(_ title: String, _ color: NSColor) -> some View {
        Button(title) { session.inkColor = color }
    }

    private func railButton(_ symbol: String, _ help: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 14))
                .frame(width: 36, height: 36)
                .foregroundStyle(active ? Theme.onInk : Theme.text)
                .background(Circle().fill(active ? Theme.ink : Color.clear))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(help)
    }
}
