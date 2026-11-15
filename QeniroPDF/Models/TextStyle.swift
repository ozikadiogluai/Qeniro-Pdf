import SwiftUI
import AppKit
import PDFKit

/// PDF Düzenle panelindeki metin biçimi.
struct TextStyle: Equatable {
    var family: String = "Arial"
    var size: CGFloat = 12
    var bold = false
    var italic = false
    var underline = false
    var color: Color = .black
    var alignment: NSTextAlignment = .left

    static let families = ["Arial", "Helvetica", "Helvetica Neue", "Times New Roman", "Georgia", "Verdana", "Courier New", "Menlo", "Avenir Next", "Gill Sans"]
    static let sizes: [CGFloat] = [6, 7, 8, 9, 10, 11, 12, 14, 16, 18, 20, 24, 28, 32, 36, 48, 60, 72]

    var nsColor: NSColor { NSColor(color) }

    func makeFont() -> NSFont {
        var traits: NSFontTraitMask = []
        if bold { traits.insert(.boldFontMask) }
        if italic { traits.insert(.italicFontMask) }
        let fm = NSFontManager.shared
        if let f = fm.font(withFamily: family, traits: traits, weight: 5, size: size) { return f }
        var f = NSFont(name: family, size: size) ?? NSFont.systemFont(ofSize: size)
        if bold { f = fm.convert(f, toHaveTrait: .boldFontMask) }
        if italic { f = fm.convert(f, toHaveTrait: .italicFontMask) }
        return f
    }

    static func from(annotation a: PDFAnnotation) -> TextStyle {
        var s = TextStyle()
        if let font = a.font {
            s.family = font.familyName ?? "Arial"
            s.size = font.pointSize
            let traits = NSFontManager.shared.traits(of: font)
            s.bold = traits.contains(.boldFontMask)
            s.italic = traits.contains(.italicFontMask)
        }
        if let c = a.fontColor { s.color = Color(nsColor: c) }
        s.alignment = a.alignment
        return s
    }
}

