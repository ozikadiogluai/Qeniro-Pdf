import SwiftUI

enum ToolGroup: String, CaseIterable, Identifiable {
    case createConvert = "Oluştur ve Dönüştür"
    case editOrganize = "Düzenle ve Organize Et"
    case signProtect = "İmzala ve Koruyun"
    var id: String { rawValue }
    /// Ekranda görünen (çevrilmiş) ad; ham değer String Catalog anahtarıdır.
    var title: String { rawValue.loc }
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
        case .create: return String(localized: "PDF Oluştur")
        case .convert: return String(localized: "PDF Dönüştür")
        case .toWord: return String(localized: "PDF'yi Word'e")
        case .toExcel: return String(localized: "PDF'yi Excel'e")
        case .toPowerPoint: return String(localized: "PDF'yi PowerPoint'e")
        case .edit: return String(localized: "PDF Düzenle")
        case .merge: return String(localized: "PDF Birleştir")
        case .split: return String(localized: "PDF Böl")
        case .organize: return String(localized: "PDF Sayfaları Düzenle")
        case .compress: return String(localized: "PDF Sıkıştır")
        case .signFill: return String(localized: "İmzala ve Doldur")
        case .certificateSign: return String(localized: "Sertifika ile İmzala")
        case .protect: return String(localized: "Koruma")
        case .redact: return String(localized: "PDF'de Sansürle")
        case .sanitize: return String(localized: "Hassas Bilgileri Kaldır")
        }
    }

    /// Ana sayfadaki daire düğmelerin kısa adı.
    var shortTitle: String {
        switch self {
        case .merge: return String(localized: "Birleştir")
        case .split: return String(localized: "Böl")
        case .compress: return String(localized: "Sıkıştır")
        case .convert: return String(localized: "Dönüştür")
        case .signFill: return String(localized: "İmzala")
        default: return title
        }
    }

    var subtitle: String {
        switch self {
        case .create: return String(localized: "Dosyalardan PDF oluşturun")
        case .convert: return String(localized: "PDF'yi Word, Excel, PowerPoint'e dönüştürün")
        case .toWord: return String(localized: "Düzenlenebilir Word belgesi (.docx) oluşturun")
        case .toExcel: return String(localized: "Tabloları Excel çalışma kitabına (.xlsx) aktarın")
        case .toPowerPoint: return String(localized: "Her sayfayı bir slayta (.pptx) dönüştürün")
        case .edit: return String(localized: "Metin ve görselleri düzenleyin")
        case .merge: return String(localized: "Birden fazla PDF'yi tek dosyada toplayın")
        case .split: return String(localized: "PDF'yi birden fazla dosyaya ayırın")
        case .organize: return String(localized: "Sayfaları sıralayın, döndürün, silin")
        case .compress: return String(localized: "Dosya boyutunu küçültün")
        case .signFill: return String(localized: "Formları doldurun ve e-imza ekleyin")
        case .certificateSign: return String(localized: "Dijital sertifika ile imzalayın")
        case .protect: return String(localized: "Şifre ile koruyun ve izinleri yönetin")
        case .redact: return String(localized: "Hassas içeriği kalıcı olarak kaldırın")
        case .sanitize: return String(localized: "Meta verileri ve gizli içeriği temizleyin")
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
        case .allTools: return String(localized: "Tüm araçlar")
        case .edit: return String(localized: "Düzenle")
        case .convert: return String(localized: "Dönüştür")
        case .sign: return String(localized: "E-imza")
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
        case .redact: return String(localized: "PDF'yi redakte et")
        case .headerFooter: return String(localized: "Üstbilgi ve altbilgi")
        case .watermark: return String(localized: "Filigran")
        case .formPrepare: return String(localized: "Form hazırla")
        case .verifySignatures: return String(localized: "İmzaları doğrula")
        }
    }
}

enum SidebarItem: String, CaseIterable, Identifiable {
    case home, tools, recent, starred, cloud
    var id: String { rawValue }
    var title: String {
        switch self {
        case .home: return String(localized: "Ana Sayfa")
        case .tools: return String(localized: "Araçlar")
        case .recent: return String(localized: "Son Dosyalar")
        case .starred: return String(localized: "Yıldızlı")
        case .cloud: return String(localized: "Bulut Depolama")
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
