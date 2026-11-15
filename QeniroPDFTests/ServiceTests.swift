import XCTest
import PDFKit
import AppKit
@testable import QeniroPDF

final class ServiceTests: XCTestCase {
    private var tmp: URL!

    override func setUpWithError() throws {
        tmp = FileManager.default.temporaryDirectory.appendingPathComponent("qeniro-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tmp)
    }

    /// Her sayfasında "Sayfa N" yazan örnek PDF üretir.
    private func makePDF(pages: Int, name: String) throws -> URL {
        let doc = PDFDocument()
        for i in 0..<pages {
            let data = PageRenderer.singlePageData(size: PageRenderer.a4) { ctx in
                ctx.setFillColor(CGColor(gray: 1, alpha: 1))
                ctx.fill(CGRect(origin: .zero, size: PageRenderer.a4))
                let attr = NSAttributedString(string: "Sayfa \(i + 1) Hizmet Sözleşmesi 1.234,56",
                                              attributes: [.font: NSFont.systemFont(ofSize: 18)])
                PageRenderer.drawAttributed(attr, in: CGRect(x: 50, y: 700, width: 480, height: 40), ctx: ctx)
            }
            let page = try XCTUnwrap(PageRenderer.page(from: data))
            doc.insert(page, at: doc.pageCount)
        }
        let url = tmp.appendingPathComponent(name)
        XCTAssertTrue(doc.write(to: url))
        return url
    }

    func testParseRanges() {
        XCTAssertEqual(DocTools.parseRanges("1-3, 5, 8-", pageCount: 10), [[0, 1, 2], [4], [7, 8, 9]])
        XCTAssertEqual(DocTools.parseRanges("12", pageCount: 10), [])
        XCTAssertEqual(DocTools.parseRanges("-2", pageCount: 5), [[0, 1]])
    }

    func testMerge() throws {
        let a = try makePDF(pages: 2, name: "a.pdf")
        let b = try makePDF(pages: 3, name: "b.pdf")
        let out = tmp.appendingPathComponent("m.pdf")
        let n = try PDFMergeService.merge([a, b], to: out)
        XCTAssertEqual(n, 5)
        XCTAssertEqual(PDFDocument(url: out)?.pageCount, 5)
    }

    func testSplitEveryPage() throws {
        let a = try makePDF(pages: 4, name: "s.pdf")
        let urls = try PDFSplitService.split(input: a, data: nil, mode: .single, folder: tmp, baseName: "s")
        XCTAssertEqual(urls.count, 4)
    }

    func testProtectAndRemove() throws {
        let a = try makePDF(pages: 1, name: "p.pdf")
        let locked = tmp.appendingPathComponent("locked.pdf")
        try PDFProtectService.protect(input: a, data: nil, output: locked,
                                      options: ProtectOptions(openPassword: "1234", permissionsPassword: "", allowPrinting: true, allowCopying: false))
        let d = try XCTUnwrap(PDFDocument(url: locked))
        XCTAssertTrue(d.isLocked)
        let open = tmp.appendingPathComponent("open.pdf")
        try PDFProtectService.removePassword(input: locked, password: "1234", output: open)
        XCTAssertFalse(try XCTUnwrap(PDFDocument(url: open)).isLocked)
    }

    func testOfficeExportsAreZip() throws {
        let a = try makePDF(pages: 2, name: "o.pdf")
        let doc = try XCTUnwrap(PDFDocument(url: a))
        for data in [try OfficeExportService.docx(doc: doc, preserveLayout: false, useOCR: false),
                     try OfficeExportService.xlsx(doc: doc, useOCR: false),
                     try OfficeExportService.pptx(doc: doc, editableText: true, useOCR: false)] {
            XCTAssertEqual(Array(data.prefix(4)), [0x50, 0x4B, 0x03, 0x04])
        }
    }

    func testNumberParsing() {
        XCTAssertEqual(OfficeExportService.number(from: "1.234,56"), 1234.56)
        XCTAssertEqual(OfficeExportService.number(from: "1234.5"), 1234.5)
        XCTAssertNil(OfficeExportService.number(from: "Hizmet"))
        XCTAssertEqual(OfficeExportService.columnName(0), "A")
        XCTAssertEqual(OfficeExportService.columnName(27), "AB")
    }

    func testCRC32() {
        XCTAssertEqual(ZipWriter.crc32(Data("123456789".utf8)), 0xCBF43926)
    }

    func testSanitize() throws {
        let a = try makePDF(pages: 1, name: "z.pdf")
        let out = tmp.appendingPathComponent("z_temiz.pdf")
        let report = try PDFSanitizeService.sanitize(input: a, data: nil, output: out, options: SanitizeOptions())
        XCTAssertFalse(report.isEmpty)
        XCTAssertNotNil(PDFDocument(url: out))
    }
}
