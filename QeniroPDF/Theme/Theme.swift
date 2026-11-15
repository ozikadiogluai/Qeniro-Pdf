import SwiftUI
import AppKit

/// Qeniro PDF renk ve tipografi tanımları (açık + koyu tema).
enum Theme {
    static func dynamic(light: NSColor, dark: NSColor) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
        })
    }

    static func hex(_ value: UInt32, alpha: CGFloat = 1) -> NSColor {
        NSColor(srgbRed: CGFloat((value >> 16) & 0xFF) / 255,
                green: CGFloat((value >> 8) & 0xFF) / 255,
                blue: CGFloat(value & 0xFF) / 255,
                alpha: alpha)
    }

    // Vurgu ve durum renkleri
    static let accentNS = hex(0xE5322D)
    static let accent = Color(nsColor: accentNS)
    static let selectionNS = hex(0x2D6BE4)
    static let selection = Color(nsColor: selectionNS)
    static let applyPurple = Color(nsColor: hex(0x6D4AE0))
    static let purple = Color(nsColor: hex(0x7C4DDB))
    static let blue = Color(nsColor: hex(0x2D6BE4))
    static let green = Color(nsColor: hex(0x1E8E3E))
    static let orange = Color(nsColor: hex(0xE8710A))

    // Yüzeyler
    static let background = dynamic(light: hex(0xF5F6F8), dark: hex(0x16171A))
    static let window = dynamic(light: .white, dark: hex(0x1E1F23))
    static let sidebar = dynamic(light: hex(0xF3F4F7), dark: hex(0x24252A))
    static let card = dynamic(light: .white, dark: hex(0x2A2B30))
    static let cardHover = dynamic(light: hex(0xFAFBFC), dark: hex(0x313238))
    static let border = dynamic(light: hex(0xE5E7EB), dark: hex(0x3A3B41))
    static let activeNav = dynamic(light: hex(0xE6EEFC), dark: hex(0x24395F))
    static let signatureBanner = dynamic(light: hex(0xDCE9FB), dark: hex(0x1F3150))
    static let noticeBackground = dynamic(light: hex(0xFFF7DA), dark: hex(0x3A3220))
    static let canvasNS = NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? hex(0x141518) : hex(0xE9EBEF)
    }
    static let secondaryText = Color.secondary

    // Ölçüler
    static let sidebarWidth: CGFloat = 190
    static let panelWidth: CGFloat = 240
    static let toolPanelWidth: CGFloat = 300
    static let cornerRadius: CGFloat = 10

    // Tipografi
    static let titleFont = Font.system(size: 22, weight: .semibold)
    static let cardTitleFont = Font.system(size: 13, weight: .semibold)
    static let captionFont = Font.system(size: 11)
    static let sectionFont = Font.system(size: 14, weight: .semibold)
}

extension View {
    /// Beyaz kart görünümü: 1 px kenarlık, 10 px köşe.
    func qCard(hover: Bool = false) -> some View {
        self
            .background(RoundedRectangle(cornerRadius: Theme.cornerRadius).fill(hover ? Theme.cardHover : Theme.card))
            .overlay(RoundedRectangle(cornerRadius: Theme.cornerRadius).stroke(hover ? Theme.selection.opacity(0.6) : Theme.border, lineWidth: 1))
    }
}
