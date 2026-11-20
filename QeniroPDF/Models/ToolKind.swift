import SwiftUI

enum ToolGroup: String, CaseIterable, Identifiable {
    case createConvert = "Oluştur ve Dönüştür"
    case editOrganize = "Düzenle ve Organize Et"
    case signProtect = "İmzala ve Koruyun"
    var id: String { rawValue }
    var tools: [ToolKind] { ToolKind.allCases.filter { $0.group == self } }
}

/// Uygulamadaki 15 aracın tamamı.
enum ToolKind: String, CaseIterable, Identifiable {
    case create, convert, toWord, toExcel, toPowerPoint
    case edit, merge, split, organize, compress
    case signFill, certificateSign, protect, redact, sanitize

    var id: String { rawValue }

    var title: String {
        switch self {
        case .create: return "PDF Oluştur"
        case .convert: return "PDF Dönüştür"
        case .toWord: return "PDF'yi Word'e"
        case .toExcel: return "PDF'yi Excel'e"
        case .toPowerPoint: return "PDF'yi PowerPoint'e"
        case .edit: return "PDF Düzenle"
        case .merge: return "PDF Birleştir"
        case .split: return "PDF Böl"
        case .organize: return "PDF Sayfaları Düzenle"
        case .compress: return "PDF Sıkıştır"
        case .signFill: return "İmzala ve Doldur"
        case .certificateSign: return "Sertifika ile İmzala"
        case .protect: return "Koruma"
        case .redact: return "PDF'de Sansürle"
        case .sanitize: return "Hassas Bilgileri Kaldır"
        }
    }

    /// Ana sayfadaki daire düğmelerin kısa adı.
    var shortTitle: String {
        switch self {
        case .merge: return "Birleştir"
        case .split: return "Böl"
        case .compress: return "Sıkıştır"
        case .convert: return "Dönüştür"
        case .signFill: return "İmzala"
        default: return title
        }
    }

    var subtitle: String {
        switch self {
        case .create: return "Dosyalardan PDF oluşturun"
        case .convert: return "PDF'yi Word, Excel, PowerPoint'e dönüştürün"
        case .toWord: return "Düzenlenebilir Word belgesi (.docx) oluşturun"
        case .toExcel: return "Tabloları Excel çalışma kitabına (.xlsx) aktarın"
        case .toPowerPoint: return "Her sayfayı bir slayta (.pptx) dönüştürün"
        case .edit: return "Metin ve görselleri düzenleyin"
        case .merge: return "Birden fazla PDF'yi tek dosyada toplayın"
        case .split: return "PDF'yi birden fazla dosyaya ayırın"
        case .organize: return "Sayfaları sıralayın, döndürün, silin"
        case .compress: return "Dosya boyutunu küçültün"
        case .signFill: return "Formları doldurun ve e-imza ekleyin"
        case .certificateSign: return "Dijital sertifika ile imzalayın"
        case .protect: return "Şifre ile koruyun ve izinleri yönetin"
        case .redact: return "Hassas içeriği kalıcı olarak kaldırın"
        case .sanitize: return "Meta verileri ve gizli içeriği temizleyin"
        }
    }

    var symbol: String {
        switch self {
        case .create: return "doc.badge.plus"
        case .convert: return "arrow.left.arrow.right.square"
        case .toWord: return "doc.richtext"
        case .toExcel: return "tablecells"
        case .toPowerPoint: return "rectangle.on.rectangle.angled"
        case .edit: return "square.and.pencil"
        case .merge: return "square.on.square"
        case .split: return "scissors"
        case .organize: return "square.grid.2x2"
        case .compress: return "arrow.down.right.and.arrow.up.left"
        case .signFill: return "signature"
        case .certificateSign: return "checkmark.seal"
        case .protect: return "lock.shield"
        case .redact: return "eye.slash"
        case .sanitize: return "trash.slash"
        }
    }

    /// Lacivert temada araç simgeleri tek renklidir (koyu ikon, kart2 daire içinde).
    var tint: Color { Theme.ink }

    var group: ToolGroup {
        switch self {
        case .create, .convert, .toWord, .toExcel, .toPowerPoint: return .createConvert
        case .edit, .merge, .split, .organize, .compress: return .editOrganize
        case .signFill, .certificateSign, .protect, .redact, .sanitize: return .signProtect
        }
    }

    /// Ana sayfadaki 8 hızlı araç.
    static let homeTools: [ToolKind] = [.edit, .create, .merge, .split, .compress, .convert, .signFill, .protect]

    /// Açık belge üzerinde sağ panel/görünüm olarak çalışan araçlar.
    var isDocumentTool: Bool {
        switch self {
        case .edit, .signFill, .organize, .redact, .certificateSign: return true
        default: return false
        }
    }
}

/// Açık belgede üstteki sekmeler (Acrobat düzeni).
enum ViewerTab: String, CaseIterable, Identifiable {
    case allTools, edit, convert, sign
    var id: String { rawValue }
    var title: String {
        switch self {
        case .allTools: return "Tüm araçlar"
        case .edit: return "Düzenle"
        case .convert: return "Dönüştür"
        case .sign: return "E-imza"
        }
    }
}

/// Soldaki araç panelinin içeriği. `.tab` seçili sekmenin ana içeriğidir; diğerleri alt panellerdir.
enum SidePanel: String, Identifiable {
    case tab, redact, headerFooter, watermark, formPrepare, verifySignatures
    var id: String { rawValue }
    var title: String {
        switch self {
        case .tab: return ""
        case .redact: return "PDF'yi redakte et"
        case .headerFooter: return "Üstbilgi ve altbilgi"
        case .watermark: return "Filigran"
        case .formPrepare: return "Form hazırla"
        case .verifySignatures: return "İmzaları doğrula"
        }
    }
}

enum SidebarItem: String, CaseIterable, Identifiable {
    case home, tools, recent, starred, cloud
    var id: String { rawValue }
    var title: String {
        switch self {
        case .home: return "Ana Sayfa"
        case .tools: return "Araçlar"
        case .recent: return "Son Dosyalar"
        case .starred: return "Yıldızlı"
        case .cloud: return "Bulut Depolama"
        }
    }
    var symbol: String {
        switch self {
        case .home: return "house"
        case .tools: return "square.grid.2x2"
        case .recent: return "clock"
        case .starred: return "star"
        case .cloud: return "cloud"
        }
    }
}
