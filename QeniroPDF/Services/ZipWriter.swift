import Foundation

/// Bağımlılıksız, sıkıştırmasız (STORE) ZIP yazıcı. OpenXML (.docx/.xlsx/.pptx) paketleri için yeterlidir.
struct ZipWriter {
    private struct Entry {
        let name: Data
        let crc: UInt32
        let size: UInt32
        let offset: UInt32
    }

    private var data = Data()
    private var entries: [Entry] = []

    init() {}

    static let crcTable: [UInt32] = (0..<256).map { i -> UInt32 in
        var c = UInt32(i)
        for _ in 0..<8 { c = (c & 1) != 0 ? (0xEDB88320 ^ (c >> 1)) : (c >> 1) }
        return c
    }

    static func crc32(_ d: Data) -> UInt32 {
        var c: UInt32 = 0xFFFFFFFF
        for b in d { c = crcTable[Int((c ^ UInt32(b)) & 0xFF)] ^ (c >> 8) }
        return c ^ 0xFFFFFFFF
    }

    private mutating func u16(_ v: UInt16) { var x = v.littleEndian; withUnsafeBytes(of: &x) { data.append(contentsOf: $0) } }
    private mutating func u32(_ v: UInt32) { var x = v.littleEndian; withUnsafeBytes(of: &x) { data.append(contentsOf: $0) } }

    // 1 Ocak 2026 00:00 (DOS tarih/saat biçimi)
    private let dosTime: UInt16 = 0
    private let dosDate: UInt16 = UInt16(((2026 - 1980) << 9) | (1 << 5) | 1)

    mutating func add(_ path: String, _ content: Data) {
        let name = Data(path.utf8)
        let crc = Self.crc32(content)
        let offset = UInt32(data.count)
        u32(0x04034b50); u16(20); u16(0x0800); u16(0); u16(dosTime); u16(dosDate)
        u32(crc); u32(UInt32(content.count)); u32(UInt32(content.count))
        u16(UInt16(name.count)); u16(0)
        data.append(name)
        data.append(content)
        entries.append(Entry(name: name, crc: crc, size: UInt32(content.count), offset: offset))
    }

    mutating func add(_ path: String, _ text: String) { add(path, Data(text.utf8)) }

    mutating func finish() -> Data {
        let cdStart = UInt32(data.count)
        for e in entries {
            u32(0x02014b50); u16(20); u16(20); u16(0x0800); u16(0); u16(dosTime); u16(dosDate)
            u32(e.crc); u32(e.size); u32(e.size)
            u16(UInt16(e.name.count)); u16(0); u16(0); u16(0); u16(0); u32(0); u32(e.offset)
            data.append(e.name)
        }
        let cdSize = UInt32(data.count) - cdStart
        u32(0x06054b50); u16(0); u16(0); u16(UInt16(entries.count)); u16(UInt16(entries.count))
        u32(cdSize); u32(cdStart); u16(0)
        return data
    }
}

extension String {
    /// XML metin içeriği için kaçış.
    var xmlEscaped: String {
        var s = ""
        s.reserveCapacity(count)
        for ch in unicodeScalars {
            switch ch {
            case "&": s += "&amp;"
            case "<": s += "&lt;"
            case ">": s += "&gt;"
            case "\"": s += "&quot;"
            case "'": s += "&apos;"
            default:
                // XML 1.0'da geçersiz kontrol karakterlerini atla
                if ch.value < 0x20 && ch != "\t" && ch != "\n" && ch != "\r" { continue }
                if ch.value == 0xFFFE || ch.value == 0xFFFF { continue }
                s.unicodeScalars.append(ch)
            }
        }
        return s
    }
}
