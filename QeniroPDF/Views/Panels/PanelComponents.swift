import SwiftUI

struct PanelHeader: View {
    let title: String
    let onClose: () -> Void

    var body: some View {
        HStack {
            Text(title).font(.title3.weight(.semibold)).foregroundStyle(Theme.text)
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
        Text(text).font(.callout).foregroundStyle(Theme.secondaryText).padding(.top, 4)
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
                    .foregroundStyle(tint ?? (active ? Theme.navy : Theme.ink))
                Text(title)
                    .foregroundStyle(tint ?? Theme.text)
                Spacer()
            }
            .font(.body)
            .padding(.horizontal, 8)
            .frame(minHeight: 34)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(active ? Theme.card2 : (hover ? Theme.card2.opacity(0.6) : Color.clear)))
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
                .font(.body)
                .frame(width: 36, height: 32)
                .background(Capsule().fill(isOn ? Theme.ink : Theme.card2))
                .foregroundStyle(isOn ? Theme.onInk : Theme.text)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}
