import Foundation
import AppKit
import CoreText

// PDFium ile PDF içindeki gerçek metin nesnelerini okuma ve değiştirme.
// Tüm çağrılar ana iş parçacığından yapılmalıdır (PDFium iş parçacığı güvenli değildir).

/// PDFium kitaplığını süreç başına bir kez başlatır.
enum PDFiumLibrary {
    private static let initialized: Bool = {
        FPDF_InitLibrary()
        return true
    }()

    static func initialize() { _ = initialized }
}

/// Sayfadaki düzenlenebilir bir metin satırı (bir veya birden çok bitişik metin nesnesi).
struct PDFTextItem: Equatable {
    var pageIndex: Int
    /// Sayfanın üst düzey nesne listesindeki sıra numaraları (artan).
    var objectIndices: [Int]
    /// Her nesnenin özgün metni (eşleştirme doğrulaması için).
    var objectTexts: [String]
    var text: String
    /// PDF kullanıcı uzayında (PDFKit sayfa koordinatları) sınır kutusu.
    var bounds: CGRect
    /// Metin nesnesinin ham yazı tipi boyutu (Tf).
    var rawFontSize: CGFloat
    /// Ekranda görünen yaklaşık punto (matris ölçeği uygulanmış).
    var visualSize: CGFloat
    var baseFontName: String
    var familyName: String
    var bold: Bool
    var italic: Bool
    var color: NSColor
    var transform: CGAffineTransform

    var isRotated: Bool { abs(transform.b) > 0.001 || abs(transform.c) > 0.001 }
}

/// Seçili metne panelden uygulanan biçim değişiklikleri (nil = değişmedi).
struct TextEditStyle {
    var family: String?
    var bold: Bool?
    var italic: Bool?
    var visualSize: CGFloat?
    var color: NSColor?
    var alignment: NSTextAlignment = .left
    var underline = false

    var changesFont: Bool { family != nil || bold != nil || italic != nil }
}

struct TextEditResult {
    var bounds: CGRect
    /// Özgün yazı tipi yeni karakterleri içermediği için benzer sistem yazı tipine geçildi mi?
    var substitutedFont: Bool
}

/// Belgedeki bir dijital imzanın ham verisi.
struct PDFRawSignature {
    var contents: Data
    var byteRange: [Int]
    var subFilter: String
    var reason: String
    var time: String
}

/// FPDF_SaveAsCopy çıktısını toplayan kutu.
final class PDFiumDataSink {
    var data = Data()
}

/// Bellekteki bir PDF'yi PDFium ile açar, metin nesnelerini düzenler ve yeniden yazar.
final class PDFiumEditor {
    private let doc: FPDF_DOCUMENT
    private let buffer: UnsafeMutableRawPointer
    private var pages: [Int: FPDF_PAGE] = [:]
    private var dirtyPages: Set<Int> = []
    private var fonts: [String: FPDF_FONT] = [:]
    private var fontInfoCache: [FPDF_FONT: FontInfo] = [:]

    init(data: Data, password: String?) throws {
        PDFiumLibrary.initialize()
        guard !data.isEmpty else { throw QPDFError.message(String(localized: "Belge verisi boş.")) }
        // PDFium, belge kapanana kadar bu belleği kullanır; kopyasını tutuyoruz.
        let buf = UnsafeMutableRawPointer.allocate(byteCount: data.count, alignment: 16)
        data.copyBytes(to: buf.assumingMemoryBound(to: UInt8.self), count: data.count)
        let loaded: FPDF_DOCUMENT?
        if let password, !password.isEmpty {
            loaded = FPDF_LoadMemDocument64(buf, data.count, password)
        } else {
            loaded = FPDF_LoadMemDocument64(buf, data.count, nil)
        }
        guard let loaded else {
            let code = FPDF_GetLastError()
            buf.deallocate()
            if code == 4 { throw QPDFError.message(String(localized: "PDF şifreli; doğru şifreyle açılamadı.")) }
            throw QPDFError.message(String(localized: "PDF, metin düzenleme motoruyla (PDFium) açılamadı (hata \(Int(code)))."))
        }
        doc = loaded
        buffer = buf
    }

    deinit {
        for p in pages.values { FPDF_ClosePage(p) }
        pages.removeAll()
        for f in fonts.values { FPDFFont_Close(f) }
        fonts.removeAll()
        FPDF_CloseDocument(doc)
        buffer.deallocate()
    }

    var pageCount: Int { Int(FPDF_GetPageCount(doc)) }

    // MARK: - Sayfa ve nesne okuma

    private func page(_ index: Int) throws -> FPDF_PAGE {
        if let p = pages[index] { return p }
        guard index >= 0, index < pageCount, let p = FPDF_LoadPage(doc, Int32(index)) else {
            throw QPDFError.message(String(localized: "Sayfa \(index + 1) yüklenemedi."))
        }
        pages[index] = p
        return p
    }

    private struct RawText {
        var index: Int
        var object: FPDF_PAGEOBJECT
        var text: String
        var bounds: CGRect
        var rawSize: CGFloat
        var visualSize: CGFloat
        var font: FPDF_FONT?
        var transform: CGAffineTransform
        var rgba: (UInt32, UInt32, UInt32, UInt32)
    }

    private struct FontInfo {
        var baseName: String
        var family: String
        var bold: Bool
        var italic: Bool
        var embedded: Bool
    }

    private func fontInfo(_ font: FPDF_FONT?) -> FontInfo {
        guard let font else {
            return FontInfo(baseName: "", family: "Arial", bold: false, italic: false, embedded: false)
        }
        if let cached = fontInfoCache[font] { return cached }
        var name = ""
        let len = FPDFFont_GetBaseFontName(font, nil, 0)
        if len > 0 {
            var bytes = [CChar](repeating: 0, count: len + 1)
            _ = FPDFFont_GetBaseFontName(font, &bytes, len)
            name = Self.utf8String(bytes)
        }
        let clean = FontResolver.cleanName(name)
        let flags = FPDFFont_GetFlags(font)
        let weight = FPDFFont_GetWeight(font)
        var angle: Int32 = 0
        _ = FPDFFont_GetItalicAngle(font, &angle)
        let lower = clean.lowercased()
        let bold = weight >= 600 || lower.contains("bold") || lower.contains("black") || lower.contains("heavy") || lower.contains("semibold")
        let italic = angle != 0 || lower.contains("italic") || lower.contains("oblique")
        let serif = flags > 0 && (flags & 2) != 0
        let fixed = flags > 0 && (flags & 1) != 0
        let info = FontInfo(baseName: clean,
                            family: FontResolver.displayFamily(baseName: clean, serif: serif, fixedPitch: fixed),
                            bold: bold, italic: italic,
                            embedded: FPDFFont_GetIsEmbedded(font) == 1)
        fontInfoCache[font] = info
        return info
    }

    private static func utf8String(_ bytes: [CChar]) -> String {
        let raw = bytes.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
        return String(decoding: raw, as: UTF8.self)
    }

    private static func utf16String(_ units: [UInt16]) -> String {
        let end = units.firstIndex(of: 0) ?? units.count
        return String(decoding: units[0..<end], as: UTF16.self)
    }

    private func objectText(_ obj: FPDF_PAGEOBJECT, textPage: FPDF_TEXTPAGE) -> String {
        let byteCount = FPDFTextObj_GetText(obj, textPage, nil, 0)
        guard byteCount > 2 else { return "" }
        var units = [UInt16](repeating: 0, count: Int(byteCount) / 2 + 1)
        _ = units.withUnsafeMutableBufferPointer { buf in
            FPDFTextObj_GetText(obj, textPage, buf.baseAddress, byteCount)
        }
        return Self.utf16String(units)
    }

    private func bounds(of obj: FPDF_PAGEOBJECT) -> CGRect? {
        var l: Float = 0, b: Float = 0, r: Float = 0, t: Float = 0
        guard FPDFPageObj_GetBounds(obj, &l, &b, &r, &t) != 0 else { return nil }
        return CGRect(x: CGFloat(min(l, r)), y: CGFloat(min(b, t)),
                      width: CGFloat(abs(r - l)), height: CGFloat(abs(t - b)))
    }

    private func matrix(of obj: FPDF_PAGEOBJECT) -> CGAffineTransform {
        var m = FS_MATRIX()
        guard FPDFPageObj_GetMatrix(obj, &m) != 0 else { return .identity }
        return CGAffineTransform(a: CGFloat(m.a), b: CGFloat(m.b), c: CGFloat(m.c),
                                 d: CGFloat(m.d), tx: CGFloat(m.e), ty: CGFloat(m.f))
    }

    private func setMatrix(_ obj: FPDF_PAGEOBJECT, _ t: CGAffineTransform) {
        var m = FS_MATRIX(a: Float(t.a), b: Float(t.b), c: Float(t.c), d: Float(t.d), e: Float(t.tx), f: Float(t.ty))
        _ = FPDFPageObj_SetMatrix(obj, &m)
    }

    /// Sayfadaki görünür metin nesneleri (yalnızca üst düzey; form XObject içindekiler hariç).
    private func rawTexts(_ page: FPDF_PAGE) -> [RawText] {
        guard let textPage = FPDFText_LoadPage(page) else { return [] }
        defer { FPDFText_ClosePage(textPage) }
        let count = FPDFPage_CountObjects(page)
        guard count > 0 else { return [] }
        var out: [RawText] = []
        for i in 0..<count {
            guard let obj = FPDFPage_GetObject(page, i), FPDFPageObj_GetType(obj) == FPDF_PAGEOBJ_TEXT else { continue }
            // Görünmez metin (ör. OCR katmanı, render mode 3) düzenlenebilir sayılmaz.
            if FPDFTextObj_GetTextRenderMode(obj).rawValue == 3 { continue }
            guard let b = bounds(of: obj) else { continue }
            let text = objectText(obj, textPage: textPage)
            var size: Float = 0
            _ = FPDFTextObj_GetFontSize(obj, &size)
            let m = matrix(of: obj)
            var visual = CGFloat(size) * sqrt(m.c * m.c + m.d * m.d)
            if visual < 0.5 { visual = max(b.height, 1) }
            var r: UInt32 = 0, g: UInt32 = 0, bl: UInt32 = 0, a: UInt32 = 255
            if FPDFPageObj_GetFillColor(obj, &r, &g, &bl, &a) == 0 { r = 0; g = 0; bl = 0; a = 255 }
            out.append(RawText(index: Int(i), object: obj, text: text, bounds: b, rawSize: CGFloat(size),
                               visualSize: visual, font: FPDFTextObj_GetFont(obj), transform: m, rgba: (r, g, bl, a)))
        }
        return out
    }

    private static func color(_ c: (UInt32, UInt32, UInt32, UInt32)) -> NSColor {
        NSColor(srgbRed: CGFloat(c.0) / 255, green: CGFloat(c.1) / 255, blue: CGFloat(c.2) / 255, alpha: CGFloat(c.3) / 255)
    }

    private static func rgba(_ color: NSColor) -> (UInt32, UInt32, UInt32, UInt32) {
        let c = color.usingColorSpace(.sRGB) ?? color.usingColorSpace(.deviceRGB) ?? .black
        func q(_ v: CGFloat) -> UInt32 { UInt32(max(0, min(255, (v * 255).rounded()))) }
        return (q(c.redComponent), q(c.greenComponent), q(c.blueComponent), q(c.alphaComponent))
    }

    /// Sayfadaki düzenlenebilir metin satırları. Aynı satırdaki, aynı yazı tipi ve renkteki
    /// bitişik nesneler tek öğe olarak birleştirilir.
    func textItems(pageIndex: Int) throws -> [PDFTextItem] {
        let p = try page(pageIndex)
        let raws = rawTexts(p).filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        var items: [PDFTextItem] = []
        var group: [RawText] = []
        var joined = ""

        func flush() {
            guard let first = group.first else { return }
            let info = fontInfo(first.font)
            var box = first.bounds
            for g in group.dropFirst() { box = box.union(g.bounds) }
            items.append(PDFTextItem(pageIndex: pageIndex,
                                     objectIndices: group.map { $0.index },
                                     objectTexts: group.map { $0.text },
                                     text: joined,
                                     bounds: box,
                                     rawFontSize: first.rawSize,
                                     visualSize: first.visualSize,
                                     baseFontName: info.baseName,
                                     familyName: info.family,
                                     bold: info.bold,
                                     italic: info.italic,
                                     color: Self.color(first.rgba),
                                     transform: first.transform))
            group = []
            joined = ""
        }

        for r in raws {
            if let last = group.last, let first = group.first {
                let size = max(first.visualSize, 1)
                let sameStyle = r.font == first.font
                    && abs(r.visualSize - first.visualSize) < size * 0.2
                    && r.rgba == first.rgba
                let unrotated = abs(r.transform.b) < 0.001 && abs(r.transform.c) < 0.001
                    && abs(first.transform.b) < 0.001 && abs(first.transform.c) < 0.001
                let sameLine = abs(r.transform.ty - last.transform.ty) < size * 0.3
                let gap = r.bounds.minX - last.bounds.maxX
                if sameStyle && unrotated && sameLine && gap > -size * 0.5 && gap < size * 1.2 {
                    if gap > size * 0.2 && !joined.hasSuffix(" ") && !r.text.hasPrefix(" ") { joined += " " }
                    joined += r.text
                    group.append(r)
                    continue
                }
                flush()
            }
            group = [r]
            joined = r.text
        }
        flush()
        return items
    }

    // MARK: - Metin düzenleme

    @discardableResult
    private func setText(_ obj: FPDF_PAGEOBJECT, _ text: String) -> Bool {
        var units = Array(text.utf16)
        units.append(0)
        let ok = units.withUnsafeBufferPointer { buf in
            FPDFText_SetText(obj, buf.baseAddress)
        }
        return ok != 0
    }

    private func readBack(_ obj: FPDF_PAGEOBJECT, page: FPDF_PAGE) -> String {
        guard let tp = FPDFText_LoadPage(page) else { return "" }
        defer { FPDFText_ClosePage(tp) }
        return objectText(obj, textPage: tp)
    }

    private static func squeezed(_ s: String) -> String {
        var out = ""
        for ch in s where !ch.isWhitespace { out.append(ch) }
        return out
    }

    /// Bir yazı tipinin bu sayfada gerçekten kullandığı karakterler (alt küme yazı tiplerinde
    /// yalnızca bunların glifi bulunduğu varsayılır).
    private func coverage(of font: FPDF_FONT?, in raws: [RawText]) -> Set<Unicode.Scalar> {
        var set = Set<Unicode.Scalar>()
        for r in raws where r.font == font { set.formUnion(r.text.unicodeScalars) }
        return set
    }

    private func loadFont(path: String) -> FPDF_FONT? {
        if let f = fonts[path] { return f }
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)), !data.isEmpty else { return nil }
        let font: FPDF_FONT? = data.withUnsafeBytes { raw -> FPDF_FONT? in
            guard let base = raw.bindMemory(to: UInt8.self).baseAddress else { return nil }
            // CID (Identity-H) yazı tipi: Türkçe dahil tüm Unicode karakterleri yazılabilir.
            return FPDFText_LoadFont(doc, base, UInt32(data.count), FPDF_FONT_TRUETYPE, 1)
        }
        if let font { fonts[path] = font }
        return font
    }

    private func loadStandardFont(_ name: String) -> FPDF_FONT? {
        let key = "std:" + name
        if let f = fonts[key] { return f }
        let font: FPDF_FONT? = FPDFText_LoadStandardFont(doc, name)
        if let font { fonts[key] = font }
        return font
    }

    /// Aile/kalın/italik için yazı tipi yükler (önce sistemdeki TrueType dosyası, yoksa standart 14 yazı tipi).
    private func resolveFont(family: String, bold: Bool, italic: Bool, postScript: String?) -> FPDF_FONT? {
        if let path = FontResolver.ttfPath(family: family, bold: bold, italic: italic, postScript: postScript),
           let f = loadFont(path: path) {
            return f
        }
        let fam = family.lowercased()
        let isSerif = fam.contains("times") || fam.contains("georgia") || (fam.contains("serif") && !fam.contains("sans"))
        let isMono = fam.contains("courier") || fam.contains("mono") || fam.contains("menlo")
        let std: String
        if isMono {
            std = "Courier" + (bold && italic ? "-BoldOblique" : bold ? "-Bold" : italic ? "-Oblique" : "")
        } else if isSerif {
            std = bold && italic ? "Times-BoldItalic" : bold ? "Times-Bold" : italic ? "Times-Italic" : "Times-Roman"
        } else {
            std = "Helvetica" + (bold && italic ? "-BoldOblique" : bold ? "-Bold" : italic ? "-Oblique" : "")
        }
        return loadStandardFont(std)
    }

    private func remove(_ obj: FPDF_PAGEOBJECT, from page: FPDF_PAGE) {
        if FPDFPage_RemoveObject(page, obj) != 0 { FPDFPageObj_Destroy(obj) }
    }

    private func insert(_ obj: FPDF_PAGEOBJECT, into page: FPDF_PAGE, at index: Int?) {
        if let index, index >= 0, index <= Int(FPDFPage_CountObjects(page)),
           FPDFPage_InsertObjectAtIndex(page, obj, index) != 0 {
            return
        }
        FPDFPage_InsertObject(page, obj)
    }

    /// Bir metin satırını yeni metinle değiştirir. Mümkünse aynı nesnede (aynı yazı tipiyle)
    /// değiştirir; yazı tipi yeni karakterleri içermiyorsa nesneyi silip aynı konum, boyut ve
    /// renkte benzer bir sistem yazı tipiyle yeni nesne ekler. Boş metin satırı siler.
    @discardableResult
    func replaceText(_ item: PDFTextItem, with newText: String, style: TextEditStyle? = nil) throws -> TextEditResult {
        let p = try page(item.pageIndex)
        let raws = rawTexts(p)
        var group = raws.filter { item.objectIndices.contains($0.index) }
        if group.count != item.objectIndices.count || group.map({ $0.text }) != item.objectTexts {
            // Nesne sırası değişmişse konum ve boyuttan yeniden bul.
            let target = item.bounds.insetBy(dx: 0.5, dy: 0.5)
            group = raws.filter { r in
                r.bounds.intersects(target)
                    && abs(r.visualSize - item.visualSize) < max(item.visualSize, 1) * 0.3
                    && !r.text.trimmingCharacters(in: .whitespaces).isEmpty
            }
        }
        group.sort { $0.index < $1.index }
        guard let first = group.first else {
            throw QPDFError.message(String(localized: "Bu metin sayfada bulunamadı. Belge değişmiş olabilir; tekrar tıklayıp deneyin."))
        }
        var oldBox = first.bounds
        for g in group.dropFirst() { oldBox = oldBox.union(g.bounds) }

        let text = newText.replacingOccurrences(of: "\r\n", with: " ").replacingOccurrences(of: "\n", with: " ")
        dirtyPages.insert(item.pageIndex)

        if text.trimmingCharacters(in: .whitespaces).isEmpty {
            for g in group.reversed() { remove(g.object, from: p) }
            return TextEditResult(bounds: oldBox, substitutedFont: false)
        }

        let info = fontInfo(first.font)
        var target: FPDF_PAGEOBJECT?
        var replaced = false

        // 1) Aynı nesnede, özgün yazı tipiyle değiştir (geri okuma ile doğrulanır).
        if style?.changesFont != true {
            let covered = coverage(of: first.font, in: raws)
            let allCovered = text.unicodeScalars.allSatisfy { covered.contains($0) }
            if allCovered || !info.embedded {
                if setText(first.object, text) {
                    if Self.squeezed(readBack(first.object, page: p)) == Self.squeezed(text) {
                        target = first.object
                    } else {
                        setText(first.object, first.text)
                    }
                }
            }
        }

        // 2) Benzer sistem yazı tipiyle yeni nesne.
        if target == nil {
            let family = style?.family ?? info.family
            let bold = style?.bold ?? info.bold
            let italic = style?.italic ?? info.italic
            let postScript: String? = style?.changesFont == true ? nil : info.baseName
            guard let newFont = resolveFont(family: family, bold: bold, italic: italic, postScript: postScript) else {
                throw QPDFError.message(String(localized: "Uygun yazı tipi yüklenemedi."))
            }
            let rawSize = first.rawSize > 0 ? first.rawSize : first.visualSize
            guard let obj = FPDFPageObj_CreateTextObj(doc, newFont, Float(rawSize)) else {
                throw QPDFError.message(String(localized: "Yeni metin nesnesi oluşturulamadı."))
            }
            guard setText(obj, text) else {
                FPDFPageObj_Destroy(obj)
                throw QPDFError.message(String(localized: "Metin yazı tipine aktarılamadı."))
            }
            var t = first.transform
            if first.rawSize <= 0 { t = CGAffineTransform(translationX: first.transform.tx, y: first.transform.ty) }
            setMatrix(obj, t)
            _ = FPDFPageObj_SetFillColor(obj, first.rgba.0, first.rgba.1, first.rgba.2, first.rgba.3)
            target = obj
            replaced = true
        }
        guard let target else { throw QPDFError.message(String(localized: "Metin değiştirilemedi.")) }

        // Eski nesneleri kaldır (yerinde düzenlenen ilk nesne hariç), yeni nesneyi aynı sıraya koy.
        for g in group.reversed() where replaced || g.object != first.object {
            remove(g.object, from: p)
        }
        if replaced { insert(target, into: p, at: first.index) }

        // Biçim değişiklikleri.
        if let style {
            if let vs = style.visualSize, first.visualSize > 0, abs(vs - first.visualSize) > 0.01 {
                let base = first.rawSize > 0 ? first.rawSize : first.visualSize
                _ = FPDFTextObj_SetFontSize(target, Float(base * vs / first.visualSize))
            }
            if let c = style.color {
                let q = Self.rgba(c)
                _ = FPDFPageObj_SetFillColor(target, q.0, q.1, q.2, q.3)
            }
        }
        var newBox = bounds(of: target) ?? oldBox
        if let style, !item.isRotated {
            var dx: CGFloat = 0
            switch style.alignment {
            case .center: dx = oldBox.midX - newBox.midX
            case .right: dx = oldBox.maxX - newBox.maxX
            default: dx = 0
            }
            if abs(dx) > 0.01 {
                FPDFPageObj_Transform(target, 1, 0, 0, 1, Double(dx), 0)
                newBox = newBox.offsetBy(dx: dx, dy: 0)
            }
            if style.underline {
                addUnderline(below: target, box: newBox, page: p, visualSize: style.visualSize ?? first.visualSize,
                             color: style.color ?? Self.color(first.rgba))
            }
        }
        return TextEditResult(bounds: newBox, substitutedFont: replaced)
    }

    private func addUnderline(below obj: FPDF_PAGEOBJECT, box: CGRect, page: FPDF_PAGE, visualSize: CGFloat, color: NSColor) {
        let t = matrix(of: obj)
        let thickness = max(0.5, visualSize * 0.06)
        let y = t.ty - visualSize * 0.12 - thickness
        guard let rect = FPDFPageObj_CreateNewRect(Float(box.minX), Float(y), Float(box.width), Float(thickness)) else { return }
        let q = Self.rgba(color)
        _ = FPDFPageObj_SetFillColor(rect, q.0, q.1, q.2, q.3)
        _ = FPDFPath_SetDrawMode(rect, FPDF_FILLMODE_WINDING, 0)
        FPDFPage_InsertObject(page, rect)
    }

    /// Sayfaya gerçek metin nesnesi ekler. `baseline`: ilk karakterin taban çizgisi başlangıcı.
    @discardableResult
    func insertText(_ text: String, pageIndex: Int, baseline: CGPoint, family: String, bold: Bool, italic: Bool,
                    size: CGFloat, color: NSColor, rotation: Int = 0, underline: Bool = false) throws -> CGRect {
        let p = try page(pageIndex)
        let clean = text.replacingOccurrences(of: "\n", with: " ")
        guard !clean.trimmingCharacters(in: .whitespaces).isEmpty else { return .zero }
        guard let newFont = resolveFont(family: family, bold: bold, italic: italic, postScript: nil),
              let obj = FPDFPageObj_CreateTextObj(doc, newFont, Float(size)) else {
            throw QPDFError.message(String(localized: "Metin nesnesi oluşturulamadı."))
        }
        guard setText(obj, clean) else {
            FPDFPageObj_Destroy(obj)
            throw QPDFError.message(String(localized: "Metin yazı tipine aktarılamadı."))
        }
        let normalized = ((rotation % 360) + 360) % 360
        let angle = CGFloat(normalized) * .pi / 180
        let t = CGAffineTransform(a: cos(angle), b: sin(angle), c: -sin(angle), d: cos(angle), tx: baseline.x, ty: baseline.y)
        setMatrix(obj, t)
        let q = Self.rgba(color)
        _ = FPDFPageObj_SetFillColor(obj, q.0, q.1, q.2, q.3)
        FPDFPage_InsertObject(p, obj)
        dirtyPages.insert(pageIndex)
        let box = bounds(of: obj) ?? .zero
        if underline && normalized == 0 {
            addUnderline(below: obj, box: box, page: p, visualSize: size, color: color)
        }
        return box
    }

    // MARK: - Üstbilgi / altbilgi / filigran

    enum HAlign { case left, center, right }

    enum NumberPosition: String, CaseIterable, Identifiable {
        case bottomRight = "Sağ alt", bottomCenter = "Orta alt", topRight = "Sağ üst"
        var id: String { rawValue }
    }

    private func pageBox(_ page: FPDF_PAGE) -> CGRect {
        var r = FS_RECTF()
        if FPDF_GetPageBoundingBox(page, &r) != 0 {
            return CGRect(x: CGFloat(min(r.left, r.right)), y: CGFloat(min(r.bottom, r.top)),
                          width: CGFloat(abs(r.right - r.left)), height: CGFloat(abs(r.top - r.bottom)))
        }
        return CGRect(x: 0, y: 0, width: CGFloat(FPDF_GetPageWidthF(page)), height: CGFloat(FPDF_GetPageHeightF(page)))
    }

    /// Hizalamaya göre yerleştirilmiş tek satır metin ekler (en üst katmana).
    private func placeLine(_ text: String, page p: FPDF_PAGE, font: FPDF_FONT, size: CGFloat, color: NSColor,
                           x: CGFloat, baselineY: CGFloat, align: HAlign) {
        guard !text.trimmingCharacters(in: .whitespaces).isEmpty,
              let obj = FPDFPageObj_CreateTextObj(doc, font, Float(size)) else { return }
        guard setText(obj, text) else { FPDFPageObj_Destroy(obj); return }
        setMatrix(obj, CGAffineTransform(translationX: x, y: baselineY))
        let w = bounds(of: obj)?.width ?? 0
        let dx: CGFloat
        switch align {
        case .left: dx = 0
        case .center: dx = -w / 2
        case .right: dx = -w
        }
        if dx != 0 { FPDFPageObj_Transform(obj, 1, 0, 0, 1, Double(dx), 0) }
        let q = Self.rgba(color)
        _ = FPDFPageObj_SetFillColor(obj, q.0, q.1, q.2, q.3)
        FPDFPage_InsertObject(p, obj)
    }

    /// Tüm sayfalara üstbilgi, altbilgi ve sayfa numarası ekler.
    /// Metinlerde {n} = sayfa no, {N} = toplam sayfa, {tarih} (veya {date}) = bugünün tarihi.
    func addHeaderFooter(header: String, footer: String, numberFormat: String?, numberPosition: NumberPosition,
                         size: CGFloat, color: NSColor, margin: CGFloat, date: String) throws {
        guard let lineFont = resolveFont(family: "Arial", bold: false, italic: false, postScript: nil) else {
            throw QPDFError.message(String(localized: "Yazı tipi yüklenemedi."))
        }
        let total = pageCount
        func expand(_ s: String, _ n: Int) -> String {
            s.replacingOccurrences(of: "{n}", with: "\(n)")
                .replacingOccurrences(of: "{N}", with: "\(total)")
                .replacingOccurrences(of: "{tarih}", with: date)
                .replacingOccurrences(of: "{date}", with: date)
        }
        for i in 0..<total {
            let p = try page(i)
            let box = pageBox(p)
            let top = box.maxY - margin - size * 0.8
            let bottom = box.minY + margin
            placeLine(expand(header, i + 1), page: p, font: lineFont, size: size, color: color, x: box.midX, baselineY: top, align: .center)
            placeLine(expand(footer, i + 1), page: p, font: lineFont, size: size, color: color, x: box.midX, baselineY: bottom, align: .center)
            if let fmt = numberFormat {
                let s = expand(fmt, i + 1)
                switch numberPosition {
                case .bottomRight:
                    placeLine(s, page: p, font: lineFont, size: size, color: color, x: box.maxX - margin, baselineY: bottom, align: .right)
                case .bottomCenter:
                    let y = footer.trimmingCharacters(in: .whitespaces).isEmpty ? bottom : bottom + size * 1.3
                    placeLine(s, page: p, font: lineFont, size: size, color: color, x: box.midX, baselineY: y, align: .center)
                case .topRight:
                    placeLine(s, page: p, font: lineFont, size: size, color: color, x: box.maxX - margin, baselineY: top, align: .right)
                }
            }
            dirtyPages.insert(i)
        }
    }

    /// Tüm sayfaların ortasına döndürülmüş, yarı saydam metin filigranı ekler.
    func addWatermark(_ text: String, size: CGFloat, color: NSColor, opacity: CGFloat, angle: CGFloat, bold: Bool) throws {
        let clean = text.replacingOccurrences(of: "\n", with: " ")
        guard !clean.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        guard let markFont = resolveFont(family: "Arial", bold: bold, italic: false, postScript: nil) else {
            throw QPDFError.message(String(localized: "Yazı tipi yüklenemedi."))
        }
        let rad = angle * .pi / 180
        var q = Self.rgba(color)
        q.3 = UInt32(max(0, min(255, (opacity * 255).rounded())))
        for i in 0..<pageCount {
            let p = try page(i)
            guard let obj = FPDFPageObj_CreateTextObj(doc, markFont, Float(size)) else { continue }
            guard setText(obj, clean) else { FPDFPageObj_Destroy(obj); continue }
            setMatrix(obj, CGAffineTransform(a: cos(rad), b: sin(rad), c: -sin(rad), d: cos(rad), tx: 0, ty: 0))
            let box = pageBox(p)
            if let b = bounds(of: obj) {
                FPDFPageObj_Transform(obj, 1, 0, 0, 1, Double(box.midX - b.midX), Double(box.midY - b.midY))
            }
            _ = FPDFPageObj_SetFillColor(obj, q.0, q.1, q.2, q.3)
            FPDFPage_InsertObject(p, obj)
            dirtyPages.insert(i)
        }
    }

    // MARK: - İmzalar

    func signatures() -> [PDFRawSignature] {
        let count = FPDF_GetSignatureCount(doc)
        guard count > 0 else { return [] }
        var out: [PDFRawSignature] = []
        for i in 0..<count {
            guard let sig = FPDF_GetSignatureObject(doc, i) else { continue }
            var contents = Data()
            let clen = FPDFSignatureObj_GetContents(sig, nil, 0)
            if clen > 0 {
                var bytes = [UInt8](repeating: 0, count: Int(clen))
                _ = bytes.withUnsafeMutableBytes { buf in
                    FPDFSignatureObj_GetContents(sig, buf.baseAddress, clen)
                }
                contents = Data(bytes)
            }
            var ranges: [Int] = []
            let rlen = FPDFSignatureObj_GetByteRange(sig, nil, 0)
            if rlen > 0 {
                var ints = [Int32](repeating: 0, count: Int(rlen))
                _ = ints.withUnsafeMutableBufferPointer { buf in
                    FPDFSignatureObj_GetByteRange(sig, buf.baseAddress, rlen)
                }
                ranges = ints.map { Int($0) }
            }
            var subFilter = ""
            let slen = FPDFSignatureObj_GetSubFilter(sig, nil, 0)
            if slen > 0 {
                var b = [CChar](repeating: 0, count: Int(slen) + 1)
                _ = FPDFSignatureObj_GetSubFilter(sig, &b, slen)
                subFilter = Self.utf8String(b)
            }
            var reason = ""
            let rsn = FPDFSignatureObj_GetReason(sig, nil, 0)
            if rsn > 2 {
                var units = [UInt16](repeating: 0, count: Int(rsn) / 2 + 1)
                _ = units.withUnsafeMutableBytes { buf in
                    FPDFSignatureObj_GetReason(sig, buf.baseAddress, rsn)
                }
                reason = Self.utf16String(units)
            }
            var time = ""
            let tlen = FPDFSignatureObj_GetTime(sig, nil, 0)
            if tlen > 0 {
                var b = [CChar](repeating: 0, count: Int(tlen) + 1)
                _ = FPDFSignatureObj_GetTime(sig, &b, tlen)
                time = Self.utf8String(b)
            }
            out.append(PDFRawSignature(contents: contents, byteRange: ranges, subFilter: subFilter, reason: reason, time: time))
        }
        return out
    }

    // MARK: - Kaydetme

    /// Değişen sayfaların içerik akışlarını yeniden üretir ve belgeyi bayt olarak döndürür.
    func save() throws -> Data {
        for i in dirtyPages {
            if let p = pages[i] { _ = FPDFPage_GenerateContent(p) }
        }
        let sink = PDFiumDataSink()
        var writer = QPDFFileWriter()
        writer.base.version = 1
        writer.base.WriteBlock = { pThis, pData, size in
            guard let pThis, let pData else { return 0 }
            let w = UnsafeMutableRawPointer(pThis).assumingMemoryBound(to: QPDFFileWriter.self)
            guard let ctx = w.pointee.context else { return 0 }
            let target = Unmanaged<PDFiumDataSink>.fromOpaque(ctx).takeUnretainedValue()
            if size > 0 {
                target.data.append(pData.assumingMemoryBound(to: UInt8.self), count: Int(size))
            }
            return 1
        }
        writer.context = Unmanaged.passUnretained(sink).toOpaque()
        // FPDF_NO_INCREMENTAL = 2: tam yeniden yazım.
        let ok: Int32 = withUnsafeMutablePointer(to: &writer) { ptr -> Int32 in
            let filePtr = UnsafeMutableRawPointer(ptr).assumingMemoryBound(to: FPDF_FILEWRITE.self)
            return FPDF_SaveAsCopy(doc, filePtr, 2)
        }
        let data = withExtendedLifetime(sink) { sink.data }
        guard ok != 0, !data.isEmpty else {
            throw QPDFError.message(String(localized: "Düzenlenen PDF yazılamadı."))
        }
        dirtyPages.removeAll()
        return data
    }
}

/// PDF yazı tipi adlarını sistemdeki TrueType dosyalarına eşler.
enum FontResolver {
    static let supplemental = "/System/Library/Fonts/Supplemental/"

    /// Aile -> [normal, kalın, italik, kalın italik] dosya adları.
    static let files: [String: [String]] = [
        "Arial": ["Arial.ttf", "Arial Bold.ttf", "Arial Italic.ttf", "Arial Bold Italic.ttf"],
        "Times New Roman": ["Times New Roman.ttf", "Times New Roman Bold.ttf", "Times New Roman Italic.ttf", "Times New Roman Bold Italic.ttf"],
        "Courier New": ["Courier New.ttf", "Courier New Bold.ttf", "Courier New Italic.ttf", "Courier New Bold Italic.ttf"],
        "Georgia": ["Georgia.ttf", "Georgia Bold.ttf", "Georgia Italic.ttf", "Georgia Bold Italic.ttf"],
        "Verdana": ["Verdana.ttf", "Verdana Bold.ttf", "Verdana Italic.ttf", "Verdana Bold Italic.ttf"],
        "Trebuchet MS": ["Trebuchet MS.ttf", "Trebuchet MS Bold.ttf", "Trebuchet MS Italic.ttf", "Trebuchet MS Bold Italic.ttf"],
        "Tahoma": ["Tahoma.ttf", "Tahoma Bold.ttf", "Tahoma.ttf", "Tahoma Bold.ttf"],
        "Arial Narrow": ["Arial Narrow.ttf", "Arial Narrow Bold.ttf", "Arial Narrow Italic.ttf", "Arial Narrow Bold Italic.ttf"]
    ]

    /// "ABCDEF+Arial-BoldMT" -> "Arial-BoldMT"
    static func cleanName(_ name: String) -> String {
        if let plus = name.firstIndex(of: "+"), name.distance(from: name.startIndex, to: plus) == 6 {
            return String(name[name.index(after: plus)...])
        }
        return name
    }

    /// Panelde gösterilecek aile adı.
    static func displayFamily(baseName: String, serif: Bool, fixedPitch: Bool) -> String {
        let n = baseName.replacingOccurrences(of: " ", with: "").lowercased()
        if n.contains("timesnewroman") || n.hasPrefix("times") { return "Times New Roman" }
        if n.contains("arialnarrow") { return "Arial Narrow" }
        if n.contains("arial") { return "Arial" }
        if n.contains("helveticaneue") { return "Helvetica Neue" }
        if n.contains("helvetica") { return "Helvetica" }
        if n.contains("courier") { return "Courier New" }
        if n.contains("georgia") { return "Georgia" }
        if n.contains("verdana") { return "Verdana" }
        if n.contains("trebuchet") { return "Trebuchet MS" }
        if n.contains("tahoma") { return "Tahoma" }
        if n.contains("menlo") { return "Menlo" }
        if n.contains("avenirnext") { return "Avenir Next" }
        if n.contains("gillsans") { return "Gill Sans" }
        if !baseName.isEmpty {
            let f = CTFontCreateWithName(baseName as CFString, 12, nil)
            if (CTFontCopyPostScriptName(f) as String) == baseName {
                return CTFontCopyFamilyName(f) as String
            }
        }
        if fixedPitch { return "Courier New" }
        if serif { return "Times New Roman" }
        return "Arial"
    }

    /// Sistem yazı tipinin (yalnızca .ttf) dosya yolu; PDFium .ttc ve CFF tabanlı .otf dosyalarını bu yolla yükleyemez.
    static func ttfPath(family: String, bold: Bool, italic: Bool, postScript: String?) -> String? {
        // 1) PDF'teki PostScript adıyla birebir sistem yazı tipi.
        if let ps = postScript, !ps.isEmpty {
            let f = CTFontCreateWithName(ps as CFString, 12, nil)
            if (CTFontCopyPostScriptName(f) as String) == ps, let path = ttf(of: f) { return path }
        }
        // 2) Aile + özellikler (NSFontManager).
        var traits: NSFontTraitMask = []
        if bold { traits.insert(.boldFontMask) }
        if italic { traits.insert(.italicFontMask) }
        if let nf = NSFontManager.shared.font(withFamily: family, traits: traits, weight: bold ? 9 : 5, size: 12),
           nf.familyName == family {
            let t = NSFontManager.shared.traits(of: nf)
            if t.contains(.boldFontMask) == bold && t.contains(.italicFontMask) == italic, let path = ttf(of: nf as CTFont) {
                return path
            }
        }
        // 3) Bilinen dosya tablosu.
        let key = tableFamily(for: family)
        let i = (bold ? 1 : 0) + (italic ? 2 : 0)
        for fam in [key, "Arial"] {
            guard let list = files[fam] else { continue }
            for idx in [i, bold ? 1 : 0, 0] {
                let path = supplemental + list[idx]
                if FileManager.default.fileExists(atPath: path) { return path }
            }
        }
        return nil
    }

    private static func ttf(of font: CTFont) -> String? {
        guard let url = CTFontCopyAttribute(font, kCTFontURLAttribute) as? URL,
              url.pathExtension.lowercased() == "ttf" else { return nil }
        return url.path
    }

    private static func tableFamily(for family: String) -> String {
        if files[family] != nil { return family }
        let f = family.lowercased()
        if f.contains("times") || f.contains("cambria") || f.contains("garamond") || f.contains("book")
            || (f.contains("serif") && !f.contains("sans")) {
            return "Times New Roman"
        }
        if f.contains("courier") || f.contains("menlo") || f.contains("monaco") || f.contains("mono") || f.contains("consolas") {
            return "Courier New"
        }
        if f.contains("georgia") { return "Georgia" }
        if f.contains("verdana") { return "Verdana" }
        if f.contains("tahoma") || f.contains("segoe") { return "Tahoma" }
        if f.contains("trebuchet") { return "Trebuchet MS" }
        return "Arial"
    }
}
