import Foundation
#if os(macOS)
import AppKit
#else
import UIKit
#endif
import PDFKit

/// Saf Swift OpenXML yazıcı: PDF -> .docx / .xlsx / .pptx (harici bağımlılık yok).
/// Metin, temel biçim (boyut, kalın, italik), tablolar ve görseller aktarılır;
/// birebir sayfa düzeni garanti edilmez.
enum OfficeExportService {

    struct TextRun {
        var text: String
        var rect: CGRect
        var size: CGFloat
        var bold: Bool
        var italic: Bool
    }

    struct Cell {
        var text: String
        var rect: CGRect
    }

    // MARK: - Metin çıkarma

    static func lines(of page: PDFPage, useOCR: Bool) -> [TextRun] {
        let box = page.bounds(for: .mediaBox)
        var out: [TextRun] = []
        if let sel = page.selection(for: box) {
            for l in sel.selectionsByLine() {
                let s = (l.string ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                guard !s.isEmpty else { continue }
                let r = l.bounds(for: page)
                var size = max(6, (r.height * 0.8).rounded())
                var bold = false, italic = false
                #if os(macOS)
                if let a = l.attributedString, a.length > 0,
                   let f = a.attribute(.font, at: 0, effectiveRange: nil) as? NSFont {
                    size = f.pointSize
                    let traits = NSFontManager.shared.traits(of: f)
                    bold = traits.contains(.boldFontMask) || (f.fontName.lowercased().contains("bold"))
                    italic = traits.contains(.italicFontMask)
                }
                #else
                if let a = l.attributedString, a.length > 0,
                   let f = a.attribute(.font, at: 0, effectiveRange: nil) as? UIFont {
                    size = f.pointSize
                    let traits = f.fontDescriptor.symbolicTraits
                    bold = traits.contains(.traitBold) || (f.fontName.lowercased().contains("bold"))
                    italic = traits.contains(.traitItalic)
                }
                #endif
                out.append(TextRun(text: s, rect: r, size: size, bold: bold, italic: italic))
            }
        }
        if out.isEmpty && useOCR {
            let ocr = (try? PDFOCRService.recognize(page: page)) ?? []
            out = ocr.map { l in
                TextRun(text: l.text,
                        rect: l.rect.offsetBy(dx: box.minX, dy: box.minY),
                        size: max(6, (l.rect.height * 0.75).rounded()), bold: false, italic: false)
            }
            .sorted { $0.rect.maxY > $1.rect.maxY }
        }
        return out
    }

    /// Ardışık satırları paragraflara birleştirir.
    static func paragraphs(_ lines: [TextRun]) -> [TextRun] {
        var paras: [TextRun] = []
        for l in lines {
            if var last = paras.last {
                let gap = last.rect.minY - l.rect.maxY
                let sameStyle = abs(last.size - l.size) < 0.6 && last.bold == l.bold && last.italic == l.italic
                if sameStyle && gap > -2 && gap < l.rect.height * 0.9 && abs(last.rect.minX - l.rect.minX) < 40 {
                    if last.text.hasSuffix("-") {
                        last.text.removeLast()
                        last.text += l.text
                    } else {
                        last.text += " " + l.text
                    }
                    last.rect = last.rect.union(l.rect)
                    paras[paras.count - 1] = last
                    continue
                }
            }
            paras.append(l)
        }
        return paras
    }

    static func jpegData(page: PDFPage, dpi: CGFloat) -> (Data, CGSize)? {
        let img = PageRenderer.displayImage(page: page, dpi: dpi)
        guard let data = PDFConvertService.encode(img, format: .jpeg, quality: 0.85) else { return nil }
        let b = page.bounds(for: .cropBox)
        let size = page.rotation % 180 != 0 ? CGSize(width: b.height, height: b.width) : b.size
        return (data, size)
    }

    // MARK: - DOCX

    static func docx(doc: PDFDocument, preserveLayout: Bool, useOCR: Bool) throws -> Data {
        var zip = ZipWriter()
        var body = ""
        var rels: [String] = []
        var imageIndex = 0
        let first = doc.page(at: 0)
        let pageSize = first.map { p -> CGSize in
            let b = p.bounds(for: .cropBox)
            return p.rotation % 180 != 0 ? CGSize(width: b.height, height: b.width) : b.size
        } ?? PageRenderer.a4
        let margin: CGFloat = preserveLayout ? 36 : 56

        func imageParagraph(_ data: Data, _ size: CGSize) -> String {
            imageIndex += 1
            let rid = "rIdImg\(imageIndex)"
            zip.add("word/media/image\(imageIndex).jpeg", data)
            rels.append("<Relationship Id=\"\(rid)\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/image\" Target=\"media/image\(imageIndex).jpeg\"/>")
            let maxW = pageSize.width - margin * 2, maxH = pageSize.height - margin * 2
            let s = min(maxW / max(size.width, 1), maxH / max(size.height, 1))
            let cx = Int(size.width * s * 12700), cy = Int(size.height * s * 12700)
            return """
            <w:p><w:pPr><w:jc w:val="center"/></w:pPr><w:r><w:drawing><wp:inline distT="0" distB="0" distL="0" distR="0"><wp:extent cx="\(cx)" cy="\(cy)"/><wp:docPr id="\(imageIndex)" name="Sayfa \(imageIndex)"/><wp:cNvGraphicFramePr><a:graphicFrameLocks xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" noChangeAspect="1"/></wp:cNvGraphicFramePr><a:graphic xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main"><a:graphicData uri="http://schemas.openxmlformats.org/drawingml/2006/picture"><pic:pic xmlns:pic="http://schemas.openxmlformats.org/drawingml/2006/picture"><pic:nvPicPr><pic:cNvPr id="\(imageIndex)" name="image\(imageIndex).jpeg"/><pic:cNvPicPr/></pic:nvPicPr><pic:blipFill><a:blip r:embed="\(rid)"/><a:stretch><a:fillRect/></a:stretch></pic:blipFill><pic:spPr><a:xfrm><a:off x="0" y="0"/><a:ext cx="\(cx)" cy="\(cy)"/></a:xfrm><a:prstGeom prst="rect"><a:avLst/></a:prstGeom></pic:spPr></pic:pic></a:graphicData></a:graphic></wp:inline></w:drawing></w:r></w:p>
            """
        }

        for i in 0..<doc.pageCount {
            guard let page = doc.page(at: i) else { continue }
            if i > 0 { body += "<w:p><w:r><w:br w:type=\"page\"/></w:r></w:p>" }
            let ls = preserveLayout ? [] : lines(of: page, useOCR: useOCR)
            if ls.isEmpty {
                if let r = jpegData(page: page, dpi: 150) { body += imageParagraph(r.0, r.1) }
                continue
            }
            let minX = ls.map { $0.rect.minX }.min() ?? 0
            for p in paragraphs(ls) {
                let indent = Int(max(0, p.rect.minX - minX) * 20)
                var rPr = ""
                if p.bold { rPr += "<w:b/>" }
                if p.italic { rPr += "<w:i/>" }
                rPr += "<w:sz w:val=\"\(max(8, Int(p.size * 2)))\"/>"
                let ind = indent > 200 ? "<w:ind w:left=\"\(indent)\"/>" : ""
                body += "<w:p><w:pPr><w:spacing w:after=\"120\"/>\(ind)</w:pPr><w:r><w:rPr>\(rPr)</w:rPr><w:t xml:space=\"preserve\">\(p.text.xmlEscaped)</w:t></w:r></w:p>"
            }
        }
        let tw = Int(pageSize.width * 20), th = Int(pageSize.height * 20), m = Int(margin * 20)
        let orient = pageSize.width > pageSize.height ? " w:orient=\"landscape\"" : ""
        body += "<w:sectPr><w:pgSz w:w=\"\(tw)\" w:h=\"\(th)\"\(orient)/><w:pgMar w:top=\"\(m)\" w:right=\"\(m)\" w:bottom=\"\(m)\" w:left=\"\(m)\" w:header=\"0\" w:footer=\"0\" w:gutter=\"0\"/></w:sectPr>"

        let document = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" xmlns:wp="http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing"><w:body>\(body)</w:body></w:document>
        """
        let styles = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <w:styles xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"><w:docDefaults><w:rPrDefault><w:rPr><w:rFonts w:ascii="Calibri" w:hAnsi="Calibri" w:eastAsia="Calibri" w:cs="Calibri"/><w:sz w:val="22"/><w:lang w:val="tr-TR"/></w:rPr></w:rPrDefault><w:pPrDefault><w:pPr><w:spacing w:after="120" w:line="259" w:lineRule="auto"/></w:pPr></w:pPrDefault></w:docDefaults><w:style w:type="paragraph" w:default="1" w:styleId="Normal"><w:name w:val="Normal"/></w:style></w:styles>
        """
        rels.append("<Relationship Id=\"rIdStyles\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles\" Target=\"styles.xml\"/>")
        zip.add("[Content_Types].xml", """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Default Extension="jpeg" ContentType="image/jpeg"/><Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/><Override PartName="/word/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.styles+xml"/></Types>
        """)
        zip.add("_rels/.rels", """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/></Relationships>
        """)
        zip.add("word/document.xml", document)
        zip.add("word/styles.xml", styles)
        zip.add("word/_rels/document.xml.rels", """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">\(rels.joined())</Relationships>
        """)
        return zip.finish()
    }

    // MARK: - XLSX

    /// Karakter konumlarından hücre adayları çıkarır (büyük boşluklar hücre ayırıcıdır).
    static func cells(of page: PDFPage) -> [Cell] {
        guard let s = page.string, !s.isEmpty else { return [] }
        let ns = s as NSString
        var cells: [Cell] = []
        var cur = ""
        var curRect = CGRect.null
        var lastRect = CGRect.null
        func flush() {
            let t = cur.trimmingCharacters(in: .whitespaces)
            if !t.isEmpty && !curRect.isNull { cells.append(Cell(text: t, rect: curRect)) }
            cur = ""
            curRect = .null
        }
        for i in 0..<ns.length {
            let ch = ns.substring(with: NSRange(location: i, length: 1))
            if ch == "\n" || ch == "\r" || ch == "\t" || ch == "\u{2028}" {
                flush(); lastRect = .null; continue
            }
            if ch == " " || ch == "\u{00A0}" {
                if !cur.isEmpty { cur += " " }
                continue
            }
            let r = page.characterBounds(at: i)
            if r.isEmpty || r.width <= 0 { cur += ch; continue }
            if !lastRect.isNull {
                let sameLine = abs(r.midY - lastRect.midY) < max(r.height, lastRect.height) * 0.5
                let gap = r.minX - lastRect.maxX
                if !sameLine || gap > max(lastRect.height * 0.9, 6) || gap < -lastRect.width * 2 { flush() }
            }
            cur += ch
            curRect = curRect.isNull ? r : curRect.union(r)
            lastRect = r
        }
        flush()
        return cells
    }

    static func table(from cells: [Cell]) -> [[String]] {
        guard !cells.isEmpty else { return [] }
        let sorted = cells.sorted { $0.rect.midY > $1.rect.midY }
        var rows: [[Cell]] = []
        for c in sorted {
            if let ref = rows.last?.first, abs(ref.rect.midY - c.rect.midY) < max(ref.rect.height, c.rect.height) * 0.5 {
                rows[rows.count - 1].append(c)
            } else {
                rows.append([c])
            }
        }
        var cols: [CGFloat] = []
        for x in cells.map({ $0.rect.minX }).sorted() {
            if let l = cols.last, x - l < 12 { continue }
            cols.append(x)
        }
        let aligned = cols.count <= 40
        return rows.map { row in
            let rs = row.sorted { $0.rect.minX < $1.rect.minX }
            guard aligned else { return rs.map { $0.text } }
            var out = [String](repeating: "", count: cols.count)
            for c in rs {
                var idx = (cols.lastIndex { $0 <= c.rect.minX + 6 }) ?? 0
                while idx < out.count && !out[idx].isEmpty { idx += 1 }
                if idx >= out.count { out.append(c.text) } else { out[idx] = c.text }
            }
            while let last = out.last, last.isEmpty { out.removeLast() }
            return out
        }
    }

    static func columnName(_ index: Int) -> String {
        var n = index + 1
        var s = ""
        while n > 0 {
            let r = (n - 1) % 26
            s = String(Character(Unicode.Scalar(UInt8(65 + r)))) + s
            n = (n - 1) / 26
        }
        return s
    }

    /// "1.234,56" / "1234.56" / "%12" gibi değerleri sayıya çevirir.
    static func number(from text: String) -> Double? {
        var t = text.trimmingCharacters(in: .whitespaces)
        t = t.replacingOccurrences(of: "₺", with: "").replacingOccurrences(of: "TL", with: "").trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty, t.count < 20 else { return nil }
        let trPattern = "^-?\\d{1,3}(\\.\\d{3})+(,\\d+)?$|^-?\\d+,\\d+$"
        let enPattern = "^-?\\d+(\\.\\d+)?$|^-?\\d{1,3}(,\\d{3})+(\\.\\d+)?$"
        if t.range(of: trPattern, options: .regularExpression) != nil {
            return Double(t.replacingOccurrences(of: ".", with: "").replacingOccurrences(of: ",", with: "."))
        }
        if t.range(of: enPattern, options: .regularExpression) != nil {
            return Double(t.replacingOccurrences(of: ",", with: ""))
        }
        return nil
    }

    static func xlsx(doc: PDFDocument, useOCR: Bool) throws -> Data {
        var zip = ZipWriter()
        var sheetsXML = ""
        var relsXML = ""
        var overrides = ""
        var sheetNumber = 0
        for i in 0..<doc.pageCount {
            guard let page = doc.page(at: i) else { continue }
            var cs = cells(of: page)
            if cs.isEmpty && useOCR {
                let box = page.bounds(for: .mediaBox)
                cs = ((try? PDFOCRService.recognize(page: page)) ?? []).map { Cell(text: $0.text, rect: $0.rect.offsetBy(dx: box.minX, dy: box.minY)) }
            }
            let rows = table(from: cs)
            sheetNumber += 1
            var sheetData = ""
            for (r, row) in rows.enumerated() {
                var rowXML = "<row r=\"\(r + 1)\">"
                for (c, value) in row.enumerated() where !value.isEmpty {
                    let ref = "\(columnName(c))\(r + 1)"
                    if let n = number(from: value) {
                        rowXML += "<c r=\"\(ref)\"><v>\(n)</v></c>"
                    } else {
                        rowXML += "<c r=\"\(ref)\" t=\"inlineStr\"><is><t xml:space=\"preserve\">\(value.xmlEscaped)</t></is></c>"
                    }
                }
                rowXML += "</row>"
                sheetData += rowXML
            }
            zip.add("xl/worksheets/sheet\(sheetNumber).xml", """
            <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
            <worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><sheetData>\(sheetData)</sheetData></worksheet>
            """)
            sheetsXML += "<sheet name=\"Sayfa \(i + 1)\" sheetId=\"\(sheetNumber)\" r:id=\"rId\(sheetNumber)\"/>"
            relsXML += "<Relationship Id=\"rId\(sheetNumber)\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet\" Target=\"worksheets/sheet\(sheetNumber).xml\"/>"
            overrides += "<Override PartName=\"/xl/worksheets/sheet\(sheetNumber).xml\" ContentType=\"application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml\"/>"
        }
        guard sheetNumber > 0 else { throw QPDFError.noPages }
        relsXML += "<Relationship Id=\"rId\(sheetNumber + 1)\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles\" Target=\"styles.xml\"/>"
        zip.add("[Content_Types].xml", """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/><Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>\(overrides)</Types>
        """)
        zip.add("_rels/.rels", """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/></Relationships>
        """)
        zip.add("xl/workbook.xml", """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><sheets>\(sheetsXML)</sheets></workbook>
        """)
        zip.add("xl/_rels/workbook.xml.rels", """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">\(relsXML)</Relationships>
        """)
        zip.add("xl/styles.xml", """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><fonts count="1"><font><sz val="11"/><name val="Calibri"/></font></fonts><fills count="2"><fill><patternFill patternType="none"/></fill><fill><patternFill patternType="gray125"/></fill></fills><borders count="1"><border><left/><right/><top/><bottom/><diagonal/></border></borders><cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs><cellXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/></cellXfs><cellStyles count="1"><cellStyle name="Normal" xfId="0" builtinId="0"/></cellStyles></styleSheet>
        """)
        return zip.finish()
    }

    // MARK: - PPTX

    static func pptx(doc: PDFDocument, editableText: Bool, useOCR: Bool) throws -> Data {
        guard doc.pageCount > 0, let first = doc.page(at: 0) else { throw QPDFError.noPages }
        let fb = first.bounds(for: .cropBox)
        var slideSize = first.rotation % 180 != 0 ? CGSize(width: fb.height, height: fb.width) : fb.size
        // PowerPoint sınırları: 1-56 inç
        let maxPt: CGFloat = 4000, minPt: CGFloat = 72
        let k = min(1, maxPt / max(slideSize.width, slideSize.height))
        slideSize = CGSize(width: max(minPt, slideSize.width * k), height: max(minPt, slideSize.height * k))
        let emu: CGFloat = 12700
        let sx = Int(slideSize.width * emu), sy = Int(slideSize.height * emu)

        var zip = ZipWriter()
        var slideIds = ""
        var presRels = "<Relationship Id=\"rId1\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/slideMaster\" Target=\"slideMasters/slideMaster1.xml\"/>"
        var overrides = ""
        let ns = "xmlns:a=\"http://schemas.openxmlformats.org/drawingml/2006/main\" xmlns:r=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships\" xmlns:p=\"http://schemas.openxmlformats.org/presentationml/2006/main\""
        let groupHeader = "<p:nvGrpSpPr><p:cNvPr id=\"1\" name=\"\"/><p:cNvGrpSpPr/><p:nvPr/></p:nvGrpSpPr><p:grpSpPr><a:xfrm><a:off x=\"0\" y=\"0\"/><a:ext cx=\"0\" cy=\"0\"/><a:chOff x=\"0\" y=\"0\"/><a:chExt cx=\"0\" cy=\"0\"/></a:xfrm></p:grpSpPr>"

        for i in 0..<doc.pageCount {
            guard let page = doc.page(at: i) else { continue }
            let n = i + 1
            var shapes = ""
            var slideRels = "<Relationship Id=\"rId1\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/slideLayout\" Target=\"../slideLayouts/slideLayout1.xml\"/>"
            let textLines = editableText && page.rotation == 0 ? lines(of: page, useOCR: useOCR) : []
            if textLines.isEmpty {
                if let r = jpegData(page: page, dpi: 150) {
                    let data = r.0, size = r.1
                    zip.add("ppt/media/image\(n).jpeg", data)
                    slideRels += "<Relationship Id=\"rId2\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/image\" Target=\"../media/image\(n).jpeg\"/>"
                    let s = min(slideSize.width / max(size.width, 1), slideSize.height / max(size.height, 1))
                    let w = size.width * s, h = size.height * s
                    let ox = Int((slideSize.width - w) / 2 * emu), oy = Int((slideSize.height - h) / 2 * emu)
                    shapes += "<p:pic><p:nvPicPr><p:cNvPr id=\"2\" name=\"Sayfa \(n)\"/><p:cNvPicPr><a:picLocks noChangeAspect=\"1\"/></p:cNvPicPr><p:nvPr/></p:nvPicPr><p:blipFill><a:blip r:embed=\"rId2\"/><a:stretch><a:fillRect/></a:stretch></p:blipFill><p:spPr><a:xfrm><a:off x=\"\(ox)\" y=\"\(oy)\"/><a:ext cx=\"\(Int(w * emu))\" cy=\"\(Int(h * emu))\"/></a:xfrm><a:prstGeom prst=\"rect\"><a:avLst/></a:prstGeom></p:spPr></p:pic>"
                }
            } else {
                let box = page.bounds(for: .cropBox)
                let s = min(slideSize.width / max(box.width, 1), slideSize.height / max(box.height, 1))
                var shapeId = 2
                for l in textLines {
                    let x = (l.rect.minX - box.minX) * s
                    let y = (box.maxY - l.rect.maxY) * s
                    let w = max(l.rect.width * s, 10), h = max(l.rect.height * s, 8)
                    let sz = max(100, Int(l.size * s * 100))
                    let b = l.bold ? " b=\"1\"" : ""
                    let it = l.italic ? " i=\"1\"" : ""
                    shapes += "<p:sp><p:nvSpPr><p:cNvPr id=\"\(shapeId)\" name=\"Metin \(shapeId)\"/><p:cNvSpPr txBox=\"1\"/><p:nvPr/></p:nvSpPr><p:spPr><a:xfrm><a:off x=\"\(Int(x * emu))\" y=\"\(Int(y * emu))\"/><a:ext cx=\"\(Int(w * emu))\" cy=\"\(Int(h * emu))\"/></a:xfrm><a:prstGeom prst=\"rect\"><a:avLst/></a:prstGeom><a:noFill/></p:spPr><p:txBody><a:bodyPr wrap=\"none\" lIns=\"0\" tIns=\"0\" rIns=\"0\" bIns=\"0\"/><a:lstStyle/><a:p><a:r><a:rPr lang=\"tr-TR\" sz=\"\(sz)\"\(b)\(it) dirty=\"0\"/><a:t>\(l.text.xmlEscaped)</a:t></a:r></a:p></p:txBody></p:sp>"
                    shapeId += 1
                }
            }
            zip.add("ppt/slides/slide\(n).xml", """
            <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
            <p:sld \(ns)><p:cSld><p:spTree>\(groupHeader)\(shapes)</p:spTree></p:cSld><p:clrMapOvr><a:masterClrMapping/></p:clrMapOvr></p:sld>
            """)
            zip.add("ppt/slides/_rels/slide\(n).xml.rels", """
            <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
            <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">\(slideRels)</Relationships>
            """)
            slideIds += "<p:sldId id=\"\(255 + n)\" r:id=\"rId\(n + 1)\"/>"
            presRels += "<Relationship Id=\"rId\(n + 1)\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/slide\" Target=\"slides/slide\(n).xml\"/>"
            overrides += "<Override PartName=\"/ppt/slides/slide\(n).xml\" ContentType=\"application/vnd.openxmlformats-officedocument.presentationml.slide+xml\"/>"
        }
        let themeRid = "rId\(doc.pageCount + 2)"
        presRels += "<Relationship Id=\"\(themeRid)\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/theme\" Target=\"theme/theme1.xml\"/>"

        zip.add("[Content_Types].xml", """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Default Extension="jpeg" ContentType="image/jpeg"/><Override PartName="/ppt/presentation.xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.presentation.main+xml"/><Override PartName="/ppt/slideMasters/slideMaster1.xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.slideMaster+xml"/><Override PartName="/ppt/slideLayouts/slideLayout1.xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.slideLayout+xml"/><Override PartName="/ppt/theme/theme1.xml" ContentType="application/vnd.openxmlformats-officedocument.theme+xml"/>\(overrides)</Types>
        """)
        zip.add("_rels/.rels", """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="ppt/presentation.xml"/></Relationships>
        """)
        zip.add("ppt/presentation.xml", """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <p:presentation \(ns) saveSubsetFonts="1"><p:sldMasterIdLst><p:sldMasterId id="2147483648" r:id="rId1"/></p:sldMasterIdLst><p:sldIdLst>\(slideIds)</p:sldIdLst><p:sldSz cx="\(sx)" cy="\(sy)"/><p:notesSz cx="6858000" cy="9144000"/><p:defaultTextStyle><a:defPPr><a:defRPr lang="tr-TR"/></a:defPPr></p:defaultTextStyle></p:presentation>
        """)
        zip.add("ppt/_rels/presentation.xml.rels", """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">\(presRels)</Relationships>
        """)
        zip.add("ppt/slideMasters/slideMaster1.xml", """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <p:sldMaster \(ns)><p:cSld><p:bg><p:bgRef idx="1001"><a:schemeClr val="bg1"/></p:bgRef></p:bg><p:spTree>\(groupHeader)</p:spTree></p:cSld><p:clrMap bg1="lt1" tx1="dk1" bg2="lt2" tx2="dk2" accent1="accent1" accent2="accent2" accent3="accent3" accent4="accent4" accent5="accent5" accent6="accent6" hlink="hlink" folHlink="folHlink"/><p:sldLayoutIdLst><p:sldLayoutId id="2147483649" r:id="rId1"/></p:sldLayoutIdLst><p:txStyles><p:titleStyle><a:lvl1pPr><a:defRPr sz="4400"/></a:lvl1pPr></p:titleStyle><p:bodyStyle><a:lvl1pPr><a:defRPr sz="1800"/></a:lvl1pPr></p:bodyStyle><p:otherStyle><a:lvl1pPr><a:defRPr sz="1800"/></a:lvl1pPr></p:otherStyle></p:txStyles></p:sldMaster>
        """)
        zip.add("ppt/slideMasters/_rels/slideMaster1.xml.rels", """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/slideLayout" Target="../slideLayouts/slideLayout1.xml"/><Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/theme" Target="../theme/theme1.xml"/></Relationships>
        """)
        zip.add("ppt/slideLayouts/slideLayout1.xml", """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <p:sldLayout \(ns) type="blank" preserve="1"><p:cSld name="Boş"><p:spTree>\(groupHeader)</p:spTree></p:cSld><p:clrMapOvr><a:masterClrMapping/></p:clrMapOvr></p:sldLayout>
        """)
        zip.add("ppt/slideLayouts/_rels/slideLayout1.xml.rels", """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/slideMaster" Target="../slideMasters/slideMaster1.xml"/></Relationships>
        """)
        zip.add("ppt/theme/theme1.xml", themeXML)
        return zip.finish()
    }

    static let themeXML: String = {
        func clr(_ name: String, _ hex: String) -> String { "<a:\(name)><a:srgbClr val=\"\(hex)\"/></a:\(name)>" }
        let fill = "<a:solidFill><a:schemeClr val=\"phClr\"/></a:solidFill>"
        let line = "<a:ln w=\"6350\"><a:solidFill><a:schemeClr val=\"phClr\"/></a:solidFill></a:ln>"
        let effect = "<a:effectStyle><a:effectLst/></a:effectStyle>"
        let font = "<a:latin typeface=\"Calibri\"/><a:ea typeface=\"\"/><a:cs typeface=\"\"/>"
        return """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <a:theme xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" name="Qeniro"><a:themeElements><a:clrScheme name="Qeniro"><a:dk1><a:sysClr val="windowText" lastClr="000000"/></a:dk1><a:lt1><a:sysClr val="window" lastClr="FFFFFF"/></a:lt1>\(clr("dk2", "1F2937"))\(clr("lt2", "F5F6F8"))\(clr("accent1", "E5322D"))\(clr("accent2", "2D6BE4"))\(clr("accent3", "1E8E3E"))\(clr("accent4", "E8710A"))\(clr("accent5", "7C4DDB"))\(clr("accent6", "6B7280"))\(clr("hlink", "2D6BE4"))\(clr("folHlink", "7C4DDB"))</a:clrScheme><a:fontScheme name="Qeniro"><a:majorFont>\(font)</a:majorFont><a:minorFont>\(font)</a:minorFont></a:fontScheme><a:fmtScheme name="Qeniro"><a:fillStyleLst>\(fill)\(fill)\(fill)</a:fillStyleLst><a:lnStyleLst>\(line)\(line)\(line)</a:lnStyleLst><a:effectStyleLst>\(effect)\(effect)\(effect)</a:effectStyleLst><a:bgFillStyleLst>\(fill)\(fill)\(fill)</a:bgFillStyleLst></a:fmtScheme></a:themeElements><a:objectDefaults/><a:extraClrSchemeLst/></a:theme>
        """
    }()
}
