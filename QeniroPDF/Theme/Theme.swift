import SwiftUI
import AppKit

/// Qeniro PDF "Lacivert" teması (Qeniro ana uygulamasının lacivert paleti), açık + koyu.
enum Theme {
    /// Açık ve koyu görünümde farklı çözülen dinamik renk.
    static func dynamicNS(light: NSColor, dark: NSColor) -> NSColor {
        NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
        }
    }

    static func dynamic(light: NSColor, dark: NSColor) -> Color {
        Color(nsColor: dynamicNS(light: light, dark: dark))
    }

    static func dynamic(_ light: UInt32, _ dark: UInt32) -> Color {
        dynamic(light: hex(light), dark: hex(dark))
    }

    static func hex(_ value: UInt32, alpha: CGFloat = 1) -> NSColor {
        NSColor(srgbRed: CGFloat((value >> 16) & 0xFF) / 255,
                green: CGFloat((value >> 8) & 0xFF) / 255,
                blue: CGFloat(value & 0xFF) / 255,
                alpha: alpha)
    }

    // MARK: - Lacivert paleti

    /// Pencere zemini.
    static let background = dynamic(0xF2F2F0, 0x0B1015)
    /// Beyaz kart.
    static let card = dynamic(0xFFFFFF, 0x161D24)
    /// İkon daireleri ve alan zemini.
    static let card2 = dynamic(0xF1F1EF, 0x1F2830)
    /// Ayırıcı çizgi.
    static let divider = dynamic(0xEDEDEB, 0x222C35)
    static let text = dynamic(0x111111, 0xFFFFFF)
    static let secondaryText = dynamic(0x6E6E6E, 0x8A96A0)
    /// Koyu ikon / birincil düğme zemini (koyuda beyaz).
    static let ink = dynamic(0x121A21, 0xFFFFFF)
    /// `ink` zemin üzerindeki yazı.
    static let onInk = dynamic(0xFFFFFF, 0x121A21)
    /// Lacivert vurgu (seçim çerçevesi, düzenleme kutusu).
    static let navy = dynamic(0x2E4A5E, 0x9DB8CC)
    /// Sayfaya kaydedilen / sayfa üstüne çizilen lacivert (sayfa her zaman beyaz olduğundan sabit).
    static let navyNS = hex(0x2E4A5E)
    static let green = Color(nsColor: hex(0x178A4C))
    static let red = Color(nsColor: hex(0xD23B2B))
    static let orange = dynamic(0xE07A1F, 0xF0A35A)
    static let pdfBadgeBackground = dynamic(light: hex(0xFBEAE7), dark: hex(0xD23B2B, alpha: 0.18))
    static let pdfBadgeText = dynamic(0xB42E22, 0xF2988D)
    /// Görüntüleyici zemini (sayfa arkası).
    static let canvasNS = dynamicNS(light: hex(0xE6E6E3), dark: hex(0x0B1015))
    static let canvas = Color(nsColor: canvasNS)
    /// Ortadaki "+" düğmesinin turuncu degradesi.
    static let plusGradient = LinearGradient(colors: [Color(nsColor: hex(0xFF8A3D)), Color(nsColor: hex(0xE8501B))],
                                             startPoint: .topLeading, endPoint: .bottomTrailing)

    /// Kahraman (üst lacivert alan) radyal degradesi: merkez sağ-alt.
    static func heroGradient(radius: CGFloat = 760, center: UnitPoint = UnitPoint(x: 0.92, y: 1.1)) -> RadialGradient {
        RadialGradient(stops: [
            .init(color: Color(nsColor: hex(0x5D7487)), location: 0),
            .init(color: Color(nsColor: hex(0x2B3B49)), location: 0.42),
            .init(color: Color(nsColor: hex(0x0D141B)), location: 0.80)
        ], center: center, startRadius: 0, endRadius: radius)
    }

    // MARK: - Eski adlar (diğer görünümler derlenmeye devam etsin; hepsi yeni palete bağlı)

    static let accentNS = hex(0xD23B2B)
    static let accent = red
    static let selectionNS = navyNS
    static let selection = navy
    static let applyPurple = ink
    static let purple = ink
    static let blue = navy
    static let window = background
    static let sidebar = background
    static let cardHover = card2
    static let border = divider
    static let activeNav = card2
    static let signatureBanner = card
    static let noticeBackground = card

    // MARK: - Ölçüler

    static let sidebarWidth: CGFloat = 220
    static let panelWidth: CGFloat = 240
    static let toolPanelWidth: CGFloat = 290
    static let cornerRadius: CGFloat = 18
    static let cardRadius: CGFloat = 22
    static let panelRadius: CGFloat = 18

    // MARK: - Tipografi (macOS metin stilleri; sistem fontu)

    static let titleFont = Font.title.weight(.bold)
    static let cardTitleFont = Font.body.weight(.semibold)
    static let captionFont = Font.callout
    static let sectionFont = Font.title3.weight(.semibold)
}

// MARK: - Görünüm (açık / koyu / sistem)

enum AppearanceChoice: String, CaseIterable, Identifiable {
    case system, light, dark
    static let storageKey = "qpdf.appearance"
    var id: String { rawValue }
    var title: String {
        switch self {
        case .system: return String(localized: "Sistemle aynı")
        case .light: return String(localized: "Açık")
        case .dark: return String(localized: "Koyu")
        }
    }

    static var current: AppearanceChoice {
        AppearanceChoice(rawValue: UserDefaults.standard.string(forKey: storageKey) ?? "") ?? .system
    }

    /// Tüm pencerelere uygular (NSApp.appearance; nil = sistem).
    @MainActor
    func apply() {
        switch self {
        case .system: NSApp.appearance = nil
        case .light: NSApp.appearance = NSAppearance(named: .aqua)
        case .dark: NSApp.appearance = NSAppearance(named: .darkAqua)
        }
    }
}

// MARK: - Kart ve cam yardımcıları

extension View {
    /// Beyaz kart: kenarlıksız, 18 pt köşe (Mac paneli).
    func qCard(hover: Bool = false, radius: CGFloat = Theme.cornerRadius) -> some View {
        self.background(RoundedRectangle(cornerRadius: radius, style: .continuous)
            .fill(hover ? Theme.card2 : Theme.card))
    }

    /// Liquid Glass (macOS 26+) ya da yarı saydam malzeme yedeği. Yalnızca kontrol katmanında kullanılır.
    @ViewBuilder
    func qGlass<S: Shape>(_ shape: S) -> some View {
        #if compiler(>=6.2)
        if #available(macOS 26, *) {
            self.glassEffect(.regular, in: shape)
        } else {
            self.background(.regularMaterial, in: shape)
                .overlay(shape.stroke(Color.white.opacity(0.35), lineWidth: 0.5))
        }
        #else
        self.background(.regularMaterial, in: shape)
            .overlay(shape.stroke(Color.white.opacity(0.35), lineWidth: 0.5))
        #endif
    }

    func qGlassCapsule() -> some View { qGlass(Capsule()) }
}

// MARK: - Düğme stilleri

/// Tek ve koyu birincil kapsül (Kaydet, Uygula, Tara…). Koyu temada beyaz zemin + koyu yazı.
struct QPrimaryButtonStyle: ButtonStyle {
    var height: CGFloat = 32
    var fullWidth = false
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .foregroundStyle(Theme.onInk)
            .padding(.horizontal, 16)
            .frame(maxWidth: fullWidth ? .infinity : nil)
            .frame(minHeight: height)
            .background(Capsule().fill(Theme.ink))
            .opacity(isEnabled ? (configuration.isPressed ? 0.8 : 1) : 0.4)
            .contentShape(Capsule())
    }
}

/// İkincil kapsül (beyaz / kart2 zemin).
struct QSecondaryButtonStyle: ButtonStyle {
    var height: CGFloat = 32
    var fullWidth = false
    var filled: Color = Theme.card2
    var foreground: Color = Theme.text
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body)
            .foregroundStyle(foreground)
            .padding(.horizontal, 14)
            .frame(maxWidth: fullWidth ? .infinity : nil)
            .frame(minHeight: height)
            .background(Capsule().fill(filled))
            .opacity(isEnabled ? (configuration.isPressed ? 0.75 : 1) : 0.4)
            .contentShape(Capsule())
    }
}

/// Yıkıcı işlem kapsülü (kırmızı).
struct QDestructiveButtonStyle: ButtonStyle {
    var fullWidth = false
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .foregroundStyle(Color.white)
            .padding(.horizontal, 16)
            .frame(maxWidth: fullWidth ? .infinity : nil)
            .frame(minHeight: 32)
            .background(Capsule().fill(Theme.red))
            .opacity(isEnabled ? (configuration.isPressed ? 0.8 : 1) : 0.4)
            .contentShape(Capsule())
    }
}

/// Panel içindeki beyaz 18 pt kart.
struct PanelCard<Content: View>: View {
    var title: String? = nil
    var spacing: CGFloat = 8
    var padding: CGFloat = 12
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: spacing) {
            if let title {
                Text(title)
                    .font(.callout)
                    .foregroundStyle(Theme.secondaryText)
            }
            content()
        }
        .padding(padding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Theme.panelRadius, style: .continuous).fill(Theme.card))
    }
}

/// Kırmızı "PDF" rozeti.
struct PDFBadge: View {
    var width: CGFloat = 28
    var height: CGFloat = 34

    var body: some View {
        Text("PDF")
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(Theme.pdfBadgeText)
            .frame(width: width, height: height)
            .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Theme.pdfBadgeBackground))
            .accessibilityHidden(true)
    }
}
