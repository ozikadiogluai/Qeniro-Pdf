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
        VStack(spacing: 6) {
            Capsule()
                .fill(Theme.border)
                .frame(width: 30, height: 4)
                .padding(.bottom, 2)
            railButton("cursorarrow", "Seç", active: session.tool == .select || session.tool == .editText) {
                session.tool = session.viewerTab == .edit ? .editText : .select
            }
            railButton("text.bubble", "Yorum (yapışkan not)", active: session.tool == .note) {
                session.tool = .note
            }
            railButton("highlighter", "Vurgula: metni sürükleyerek seçin", active: session.tool == .markup(.highlight)) {
                session.tool = .markup(.highlight)
            }
            railButton("scribble", "Çiz (serbest çizim)", active: session.tool == .ink) {
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
                    colorItem("Kırmızı", NSColor(srgbRed: 0.90, green: 0.20, blue: 0.18, alpha: 1))
                    colorItem("Mavi", NSColor(srgbRed: 0.18, green: 0.42, blue: 0.89, alpha: 1))
                    colorItem("Yeşil", NSColor(srgbRed: 0.12, green: 0.56, blue: 0.24, alpha: 1))
                    colorItem("Siyah", NSColor.black)
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 17, weight: .semibold))
                    .frame(width: 40, height: 40)
                    .foregroundStyle(isMoreActive ? Color.white : Color.primary)
                    .background(RoundedRectangle(cornerRadius: 8).fill(isMoreActive ? Theme.selection : Color.clear))
                    .contentShape(Rectangle())
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Diğer: altını çiz, üstünü çiz, şekil")
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 6)
        .background(RoundedRectangle(cornerRadius: 10).fill(Theme.window))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.border, lineWidth: 1))
        .shadow(color: .black.opacity(0.08), radius: 6, y: 2)
    }

    private func colorItem(_ title: String, _ color: NSColor) -> some View {
        Button(title) { session.inkColor = color }
    }

    private func railButton(_ symbol: String, _ help: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 17))
                .frame(width: 40, height: 40)
                .foregroundStyle(active ? Color.white : Color.primary)
                .background(RoundedRectangle(cornerRadius: 8).fill(active ? Theme.selection : Color.clear))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
    }
}
