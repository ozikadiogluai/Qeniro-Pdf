import SwiftUI

struct PanelHeader: View {
    let title: String
    let onClose: () -> Void

    var body: some View {
        HStack {
            Text(title).font(.system(size: 14, weight: .semibold))
            Spacer()
            Button(action: onClose) {
                Image(systemName: "xmark").font(.system(size: 11, weight: .semibold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Paneli kapat")
        }
    }
}

struct PanelSectionTitle: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text).font(.system(size: 13, weight: .semibold)).padding(.top, 4)
    }
}

/// Sağ paneldeki ikon + etiket satırı.
struct PanelRow: View {
    let symbol: String
    let title: String
    var active: Bool = false
    var tint: Color? = nil
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: symbol)
                    .frame(width: 20)
                    .foregroundStyle(tint ?? (active ? Theme.selection : Color.primary))
                Text(title)
                    .foregroundStyle(tint ?? (active ? Theme.selection : Color.primary))
                Spacer()
            }
            .font(.system(size: 13))
            .padding(.vertical, 6)
            .padding(.horizontal, 6)
            .background(RoundedRectangle(cornerRadius: 6).fill(active ? Theme.activeNav : (hover ? Theme.activeNav.opacity(0.5) : Color.clear)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }
}

/// B / I / U gibi aç-kapa düğmesi.
struct ToggleGlyph: View {
    let label: Text
    let isOn: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            label
                .frame(width: 30, height: 24)
                .background(RoundedRectangle(cornerRadius: 5).fill(isOn ? Theme.activeNav : Color.clear))
                .foregroundStyle(isOn ? Theme.selection : Color.primary)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
