import SwiftUI
import UIKit

extension UIColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(red: CGFloat((hex >> 16) & 0xFF) / 255,
                  green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255,
                  alpha: alpha)
    }

    /// Açık ve koyu temada farklı çözülen renk.
    static func dynamic(light: UIColor, dark: UIColor) -> UIColor {
        UIColor { tc in tc.userInterfaceStyle == .dark ? dark : light }
    }
}

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(uiColor: UIColor(hex: hex, alpha: CGFloat(opacity)))
    }

    /// Açık ve koyu temada farklı renk.
    static func dynamic(_ light: UInt32, _ dark: UInt32) -> Color {
        Color(uiColor: UIColor.dynamic(light: UIColor(hex: light), dark: UIColor(hex: dark)))
    }

    static func dynamic(light: UIColor, dark: UIColor) -> Color {
        Color(uiColor: UIColor.dynamic(light: light, dark: dark))
    }
}

/// Qeniro PDF "Lacivert" teması (Qeniro ana uygulamasının lacivert paleti), açık + koyu.
enum Theme {
    // MARK: Lacivert paleti

    static let background = Color.dynamic(0xF2F2F0, 0x0B1015)
    static let card = Color.dynamic(0xFFFFFF, 0x161D24)
    /// İkon daireleri, alan zemini.
    static let card2 = Color.dynamic(0xF1F1EF, 0x1F2830)
    static let divider = Color.dynamic(0xEDEDEB, 0x222C35)
    static let text = Color.dynamic(0x111111, 0xFFFFFF)
    static let secondary = Color.dynamic(0x6E6E6E, 0x8A96A0)
    /// Koyu ikon / birincil düğme zemini (koyuda beyaz).
    static let ink = Color.dynamic(0x121A21, 0xFFFFFF)
    static let onInk = Color.dynamic(0xFFFFFF, 0x121A21)
    /// Lacivert vurgu (seçim çerçevesi, düzenleme kutusu, bağlantılar).
    static let navy = Color.dynamic(0x2E4A5E, 0x9DB8CC)
    /// Sayfa üstüne çizilen lacivert (sayfa her zaman beyaz olduğundan sabit).
    static let navyUI = UIColor(hex: 0x2E4A5E)
    /// Hap menü zemini.
    static let pill = Color.dynamic(0x121A21, 0x1C252E)
    static let green = Color(hex: 0x178A4C)
    static let red = Color(hex: 0xD23B2B)
    static let orange = Color.dynamic(0xE07A1F, 0xF0A35A)
    static let pdfBadgeBackground = Color.dynamic(light: UIColor(hex: 0xFBEAE7), dark: UIColor(hex: 0xD23B2B, alpha: 0.18))
    static let pdfBadgeText = Color.dynamic(0xB42E22, 0xF2988D)
    /// Görüntüleyici zemini (sayfa arkası).
    static let viewerBackground = Color.dynamic(0xE6E6E3, 0x0B1015)
    static let grabber = Color.dynamic(0xC9C9C5, 0x222C35)
    static let chevron = Color.dynamic(0x9A9A96, 0x8A96A0)
    /// Ortadaki "+" düğmesinin turuncu degradesi.
    static let plusGradient = LinearGradient(colors: [Color(hex: 0xFF8A3D), Color(hex: 0xE8501B)],
                                             startPoint: .topLeading, endPoint: .bottomTrailing)

    /// Kahraman (üst lacivert alan) radyal degradesi: merkez sağ-alt.
    static func heroGradient(radius: CGFloat = 560) -> RadialGradient {
        RadialGradient(stops: [
            .init(color: Color(hex: 0x5D7487), location: 0),
            .init(color: Color(hex: 0x2B3B49), location: 0.40),
            .init(color: Color(hex: 0x0D141B), location: 0.78)
        ], center: UnitPoint(x: 0.88, y: 1.0), startRadius: 0, endRadius: radius)
    }

    // MARK: Eski adlar (diğer görünümler derlenmeye devam etsin; hepsi yeni palete bağlı)

    static let accent = red
    static let accentUI = UIColor(hex: 0xD23B2B)
    static let blue = navy
    static let purple = ink
    static let indigo = ink
    static let pink = ink
    static let leaf = ink
    static let star = orange
    static let border = divider
    static let tertiary = text
    static let segmentBackground = card
    static let padBackground = card
    static let chipSelected = card2
    static let hintBackground = card
    static let hintBorder = divider
    static let hintIcon = navy
    static let barBackground = background

    // MARK: Ölçüler

    static let cardRadius: CGFloat = 22
    static let sheetRadius: CGFloat = 34
}

// MARK: - Görünüm (açık / koyu / sistem)

enum AppearanceChoice: String, CaseIterable, Identifiable {
    case system, light, dark
    static let storageKey = "qpdf.appearance"
    var id: String { rawValue }
    var title: String {
        switch self {
        case .system: return "Sistemle aynı"
        case .light: return "Açık"
        case .dark: return "Koyu"
        }
    }

    var style: UIUserInterfaceStyle {
        switch self {
        case .system: return .unspecified
        case .light: return .light
        case .dark: return .dark
        }
    }

    /// Tüm pencerelere uygular (sayfalar ve paneller dahil).
    @MainActor
    func apply() {
        for scene in UIApplication.shared.connectedScenes {
            guard let ws = scene as? UIWindowScene else { continue }
            for w in ws.windows { w.overrideUserInterfaceStyle = style }
        }
    }
}

// MARK: - Kart ve cam

/// Beyaz kart, kenarlıksız, 22 pt köşe.
struct CardBackground: ViewModifier {
    var radius: CGFloat = Theme.cardRadius
    func body(content: Content) -> some View {
        content
            .background(Theme.card, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
    }
}

extension View {
    func card(radius: CGFloat = Theme.cardRadius) -> some View { modifier(CardBackground(radius: radius)) }

    /// Liquid Glass (iOS 26+) ya da yarı saydam malzeme yedeği. Yalnızca kontrol katmanında kullanılır.
    @ViewBuilder
    func qGlass<S: Shape>(_ shape: S) -> some View {
        #if compiler(>=6.2)
        if #available(iOS 26, *) {
            self.glassEffect(.regular, in: shape)
        } else {
            self.background(.ultraThinMaterial, in: shape)
                .overlay(shape.stroke(Color.white.opacity(0.45), lineWidth: 0.5))
        }
        #else
        self.background(.ultraThinMaterial, in: shape)
            .overlay(shape.stroke(Color.white.opacity(0.45), lineWidth: 0.5))
        #endif
    }

    func qGlassCapsule() -> some View { qGlass(Capsule()) }
}

/// Kart içindeki küçük bölüm başlığı.
struct SectionLabel: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.footnote)
            .foregroundStyle(Theme.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Alt panellerin üstündeki tutamak.
struct Grabber: View {
    var body: some View {
        Capsule().fill(Theme.grabber).frame(width: 36, height: 5)
    }
}

/// Sheet üst satırı: Vazgeç (sol) · başlık · birincil eylem (sağ).
struct SheetHeader: View {
    let title: String
    var cancelTitle = "Vazgeç"
    var primaryTitle: String?
    var onCancel: () -> Void
    var onPrimary: (() -> Void)?

    var body: some View {
        HStack(spacing: 8) {
            Button(action: onCancel) {
                Text(cancelTitle)
                    .font(.subheadline)
                    .foregroundStyle(Theme.text)
                    .padding(.horizontal, 16)
                    .frame(minHeight: 44)
                    .background(Theme.card, in: Capsule())
            }
            .buttonStyle(.plain)
            Text(title)
                .font(.headline)
                .foregroundStyle(Theme.text)
                .lineLimit(1)
                .frame(maxWidth: .infinity)
            if let primaryTitle, let onPrimary {
                Button(action: onPrimary) {
                    Text(primaryTitle)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.onInk)
                        .padding(.horizontal, 18)
                        .frame(minHeight: 44)
                        .background(Theme.ink, in: Capsule())
                }
                .buttonStyle(.plain)
            } else {
                Color.clear.frame(width: 80, height: 44)
            }
        }
        .padding(.horizontal, 2)
    }
}
