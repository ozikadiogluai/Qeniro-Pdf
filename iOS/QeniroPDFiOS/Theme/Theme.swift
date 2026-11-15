import SwiftUI
import UIKit

extension UIColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(red: CGFloat((hex >> 16) & 0xFF) / 255,
                  green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255,
                  alpha: alpha)
    }
}

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(uiColor: UIColor(hex: hex, alpha: CGFloat(opacity)))
    }

    /// Açık ve koyu temada farklı renk.
    static func dynamic(_ light: UInt32, _ dark: UInt32) -> Color {
        Color(uiColor: UIColor { tc in
            tc.userInterfaceStyle == .dark ? UIColor(hex: dark) : UIColor(hex: light)
        })
    }
}

/// Onaylanan iPhone tasarımının renkleri (koyu tema karşılıklarıyla).
enum Theme {
    static let accent = Color(hex: 0xE5322D)
    static let accentUI = UIColor(hex: 0xE5322D)
    static let blue = Color(hex: 0x2D6BE4)
    static let purple = Color(hex: 0x7C4DDB)
    static let indigo = Color(hex: 0x4F5BD5)
    static let green = Color(hex: 0x1E8E3E)
    static let orange = Color(hex: 0xE8710A)
    static let pink = Color(hex: 0xD2338A)
    static let leaf = Color(hex: 0x5BA632)
    static let star = Color(hex: 0xF5A524)

    static let background = Color.dynamic(0xF5F6F8, 0x0F1013)
    static let viewerBackground = Color.dynamic(0xE9EBEE, 0x08090B)
    static let card = Color.dynamic(0xFFFFFF, 0x1C1D21)
    static let border = Color.dynamic(0xE3E6EA, 0x2F3238)
    static let divider = Color.dynamic(0xEEF0F3, 0x272A2F)
    static let text = Color.dynamic(0x1C1F24, 0xF1F2F4)
    static let secondary = Color.dynamic(0x5B6270, 0x9AA1AD)
    static let tertiary = Color.dynamic(0x3E4450, 0xC4C8D0)
    static let chevron = Color.dynamic(0xA3A9B3, 0x5F6570)
    static let grabber = Color.dynamic(0xD5D9DF, 0x4A4E56)
    static let segmentBackground = Color.dynamic(0xF0F1F4, 0x2A2C31)
    static let padBackground = Color.dynamic(0xFAFBFC, 0x16171A)
    static let chipSelected = Color.dynamic(0xE8F0FD, 0x1B2A48)
    static let pdfBadgeBackground = Color.dynamic(0xFDECEC, 0x3A1B1B)
    static let pdfBadgeText = Color.dynamic(0xC62A25, 0xFF7B76)
    static let hintBackground = Color.dynamic(0xFFF7DA, 0x332B12)
    static let hintBorder = Color.dynamic(0xF1DE9B, 0x5A4A1C)
    static let hintIcon = Color(hex: 0xB7861A)
    static let barBackground = Color.dynamic(0xFFFFFF, 0x17181B)

    static let cardRadius: CGFloat = 14
}

/// Beyaz kart, 1 pt kenarlık, 14 pt köşe.
struct CardBackground: ViewModifier {
    var radius: CGFloat = Theme.cardRadius
    func body(content: Content) -> some View {
        content
            .background(Theme.card, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(Theme.border, lineWidth: 1))
    }
}

extension View {
    func card(radius: CGFloat = Theme.cardRadius) -> some View { modifier(CardBackground(radius: radius)) }
}

/// Bölüm başlığı: 12 pt, kalın, harf aralıklı, büyük harf.
struct SectionLabel: View {
    let text: String
    var body: some View {
        Text(text.uppercased(with: Locale(identifier: "tr_TR")))
            .font(.system(size: 12, weight: .semibold))
            .tracking(0.96)
            .foregroundStyle(Theme.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Alt panellerin üstündeki tutamak.
struct Grabber: View {
    var body: some View {
        Capsule().fill(Theme.grabber).frame(width: 38, height: 5)
    }
}
