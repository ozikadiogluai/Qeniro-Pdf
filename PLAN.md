# Qeniro PDF — macOS Uygulaması Geliştirme Planı

> Hedef: Ekran görüntüsündeki Qeniro PDF'in **macOS'ta sorunsuz çalışan, tüm özelliklere sahip, tam sürüm** native uygulaması.
> Hazırlayan: Claude · Tarih: 2026-11-05 · Uygulayan: Opus (otonom)

---

## 0. Karar Özeti (neden bu teknoloji?)

| Konu | Karar | Gerekçe |
|---|---|---|
| Platform | **macOS 14+ (Sonoma ve üstü)** | Modern SwiftUI API'leri, PDFKit'in en kararlı sürümü |
| Dil / UI | **Swift 5.10 + SwiftUI** (gerekirse AppKit köprüsü) | Kullanıcının Garage macOS uygulamasıyla aynı yaklaşım; en "sorunsuz" yol |
| PDF motoru | **PDFKit** (Apple, ücretsiz, yerleşik) | Görüntüleme, açıklama, form, birleştirme, bölme, şifreleme, imza için yeterli |
| OCR | **Vision framework** (Apple, yerleşik) | Taranmış PDF'lerde Türkçe dahil metin tanıma |
| Sıkıştırma | PDFKit + Quartz filtreleri + görsel yeniden örnekleme | Harici kütüphane gerekmez |
| Office dönüştürme | **Faz 3** — ayrı karar (aşağıda) | PDFKit bunu yapmaz; en zor özellik |
| Proje üretimi | **XcodeGen (`project.yml`)** → `.xcodeproj` | Elle pbxproj yazmaktan güvenli; `brew install xcodegen` |
| Dağıtım | Yerel çalıştırma / Developer ID gerektirmeyen `.app` | Ücretli Apple Developer hesabı **yok** → App Store hedeflenmiyor |
| Dil | Tüm arayüz **Türkçe** | Ekran görüntüsüyle birebir |

**Önemli kısıt:** Claude'un terminali Linux sanal makinesinde çalışır, Xcode'u çalıştıramaz. Kodu klasöre yazar, kullanıcı (veya bilgisayar kontrolü ile Claude) Xcode'da derler. Bu yüzden her fazın sonunda `build.sh` ile derlenebilir, hatasız bir durum bırakılmalı.

---

## 1. Ekran Görüntüsünden Çıkarılan Özellik Listesi

### Ana Sayfa (Hoş Geldiniz)
- Sol kenar çubuğu: Ana Sayfa · Araçlar · Son Dosyalar · Yıldızlı · Bulut Depolama
- 8 hızlı araç kartı: PDF Düzenle, PDF Oluştur, PDF Birleştir, PDF Böl, PDF Sıkıştır, PDF Dönüştür, İmzala ve Doldur, Koruma
- Son Dosyalar listesi (ad, boyut, tarih, ⋮ menü)
- Sağ üst: Yardım · Bildirim · Hesap

### Tüm Araçlar sayfası (3 grup, 15 araç)
- **Oluştur ve Dönüştür:** PDF Oluştur, PDF Dönüştür, PDF'yi Word'e, PDF'yi Excel'e, PDF'yi PowerPoint'e
- **Düzenle ve Organize Et:** PDF Düzenle, PDF Birleştir, PDF Böl, PDF Sayfaları Düzenle, PDF Sıkıştır
- **İmzala ve Koruyun:** İmzala ve Doldur, Sertifika ile İmzala, Koruma, PDF'de Sansürle, Hassas Bilgileri Kaldır

### Belge görüntüleyici
- Sekmeler: Ana Sayfa | Araçlar | (açık dosya adı)
- Araç çubuğu: Kaydet, Yıldızla, Yazdır, Ara, Seçim aracı, sayfa 1/5, El aracı, Yakınlaştır/uzaklaştır, %100 ▾, Döndür
- Sağ panel **PDF Düzenle:** Metin (font, boyut, B/I/U, renk, hizalama) · Nesneler (Metin ekle, Görsel ekle, Bağlantı ekle)
- Sağ panel **İmzala ve Doldur:** İmza ekle (kayıtlı imza), Yeni imza oluştur, Metin Ekle, Onay Kutusu, Radyo Düğmesi, Tarih Ekle, **Uygula** düğmesi
- Sayfa üstünde seçilebilir/taşınabilir öğeler (mavi tutamaçlı kutu)

---

## 2. Mimari

```
QeniroPDF/
├── project.yml                 # XcodeGen tanımı
├── build.sh                    # xcodegen + xcodebuild (Debug)
├── QeniroPDF/
│   ├── App/                    # @main, AppDelegate, pencere/menü, DocumentGroup
│   ├── Models/                 # PDFDocumentModel, RecentFile, Signature, ToolDefinition
│   ├── Services/               # Her özellik bir servis (test edilebilir, UI'dan bağımsız)
│   │   ├── PDFMergeService, PDFSplitService, PDFCompressService
│   │   ├── PDFProtectService (şifre/izin), PDFRedactService
│   │   ├── PDFOCRService (Vision), PDFCreateService (görsel/metin → PDF)
│   │   ├── SignatureService (çizim/yazı/görsel imza, Keychain'de saklama)
│   │   ├── FormService (PDFKit widget ekleme), ConvertService (Faz 3)
│   │   └── RecentFilesStore, FavoritesStore, CloudStore (iCloud Drive)
│   ├── Views/
│   │   ├── Shell/              # Sidebar, sekmeler, üst çubuk
│   │   ├── Home/               # Hoş Geldiniz, araç kartları, son dosyalar
│   │   ├── Tools/              # Tüm Araçlar
│   │   ├── Viewer/             # PDFView sarmalayıcı (NSViewRepresentable), araç çubuğu
│   │   ├── Panels/             # PDFDüzenle, İmzalaVeDoldur, Sayfalar, Koruma… sağ paneller
│   │   └── Components/         # ToolCard, PanelSection, Toggle grupları
│   ├── Theme/                  # Renkler (kırmızı #E5322D vurgu, mavi seçim), tipografi, boşluk
│   ├── Resources/              # Assets.xcassets, Localizable.strings (tr), uygulama ikonu
│   └── Info.plist
└── QeniroPDFTests/             # Servis birim testleri (örnek PDF'lerle)
```

- **Pattern:** MVVM. Her sağ panelin bir ViewModel'i var; servisler saf Swift, `async/await`.
- **Belge modeli:** `PDFDocument` (PDFKit) tek kaynak; değişiklikler `UndoManager` ile geri alınabilir.
- **Çoklu belge:** Sekme başına bir `DocumentSession`.

---

## 3. Fazlar ve Yapılacaklar

### Faz 0 — Görsel ön izleme (kullanıcı tercihi: "önce görsel olarak göreyim")
- [ ] macOS görünümünde (trafik ışıkları, SF Pro, sidebar) 4 ekranın HTML mock'u: Ana Sayfa, Tüm Araçlar, Düzenleyici, İmzala ve Doldur
- [ ] Açık + koyu tema
- [ ] Kullanıcıya göster, onay sonrası Faz 1'e geç (onay gelmezse Faz 1'e devam et, tasarım sonradan uyarlanır)

### Faz 1 — İskelet + Görüntüleyici (ilk derlenebilir sürüm)
- [ ] `project.yml`, `build.sh`, Info.plist (dosya türü ilişkilendirme: `com.adobe.pdf`), sandbox + dosya erişimi entitlements
- [ ] Kabuk: sidebar, sekme çubuğu, üst sağ ikonlar
- [ ] Ana Sayfa: araç kartları, Son Dosyalar (UserDefaults + security-scoped bookmark)
- [ ] Tüm Araçlar sayfası
- [ ] PDF görüntüleyici: aç (dialog, sürükle-bırak, Finder'dan çift tık), sayfa gezinme, zoom, döndür, el/seçim aracı, arama (vurgulu), yazdır, kaydet / farklı kaydet
- [ ] Yıldızlı ve Bulut Depolama (iCloud Drive klasörü listesi)
- [ ] Tema dosyası, Türkçe strings
- [ ] **Derle, hatasız çalıştığını doğrula**

### Faz 2 — Düzenleme, Organize, İmza, Koruma
- [ ] **PDF Düzenle paneli:** metin kutusu ekle/taşı/boyutlandır (FreeText annotation), font/boyut/B-I-U/renk/hizalama, görsel ekle (Stamp annotation), bağlantı ekle (Link annotation); mevcut metni seç-düzenle (PDFKit sınırlı → mevcut metnin üzerine beyaz dikdörtgen + yeni FreeText yaklaşımı, kullanıcıya açıkça belirt)
- [ ] **İmzala ve Doldur:** imza çiz (trackpad), yaz (el yazısı fontu), görsel yükle; imzaları Keychain/Application Support'ta sakla; metin, onay kutusu, radyo, tarih alanı ekle; **Uygula** ile düzleştir (flatten)
- [ ] **Sertifika ile İmzala:** Keychain'deki sertifiklerle görünür dijital imza (Security framework, CMS) — yoksa "sertifika bulunamadı" akışı
- [ ] **PDF Birleştir:** çoklu dosya, sıralama, önizleme
- [ ] **PDF Böl:** sayfa aralığı / her N sayfa / tek tek
- [ ] **Sayfaları Düzenle:** küçük resim ızgarası, sürükle-sırala, döndür, sil, çıkar, boş sayfa ekle
- [ ] **PDF Sıkıştır:** 3 seviye (düşük/orta/yüksek), görselleri yeniden örnekle, önce/sonra boyut
- [ ] **Koruma:** açma şifresi, izin şifresi (yazdırma/kopyalama kısıtı), şifre kaldırma
- [ ] **Sansürle:** alan seç → içeriği gerçekten kaldır (sayfayı rasterize edip yeniden yaz, yalnızca üstünü örtme DEĞİL)
- [ ] **Hassas Bilgileri Kaldır:** metadata, yorumlar, ekler, gömülü JS, form verisi temizleme
- [ ] **PDF Oluştur:** görsellerden, boş sayfadan, panodan/metinden, Word/Pages/Numbers dosyalarını macOS'un yerleşik yazdırma motoruyla (NSDocument/`qlmanage`/Automator'suz, `NSPrintOperation`) PDF'e çevirme
- [ ] Geri al / yinele, klavye kısayolları (⌘O, ⌘S, ⌘P, ⌘F, ⌘+/−)
- [ ] **Derle, her aracı örnek PDF ile test et**

### Faz 3 — Dönüştürme ve OCR
- [ ] **OCR (Vision):** taranmış sayfalara görünmez metin katmanı (aranabilir PDF)
- [ ] **PDF → Word/Excel/PowerPoint:** Karar seçenekleri (Opus en güvenlisini seçsin, gerekçeyi README'ye yazsın):
  1. Uygulama içine gömülü Python (pdf2docx / camelot / python-pptx) — kurulum ağır
  2. Saf Swift ile kendi `.docx/.xlsx/.pptx` yazıcı (OpenXML ZIP) — metin + görsel + tablo düzeyinde, sayfa düzenini korumaya çalışır → **önerilen**, bağımlılıksız
  3. LibreOffice varsa `soffice --headless` köprüsü (isteğe bağlı hızlandırıcı)
- [ ] **PDF Dönüştür:** PDF → görsel (PNG/JPEG, çözünürlük seçimi), PDF → metin, PDF/A
- [ ] Toplu işlem (birden fazla dosya)

### Faz 4 — Cila ve Sağlamlık
- [ ] Uygulama ikonu (kırmızı rozet, "Q" veya PDF simgesi — kendi özgün tasarımımız)
- [ ] Koyu tema, Retina ikonlar, pencere boyutu/konumu hatırlama
- [ ] Hata yakalama: bozuk PDF, şifreli PDF açma, büyük dosya (500+ sayfa) performansı
- [ ] Birim testleri: her servis için örnek PDF ile
- [ ] `README.md`: kurulum, derleme, özellik durumu tablosu, bilinen sınırlar
- [ ] İsteğe bağlı: Sparkle ile otomatik güncelleme, Homebrew cask

---

## 4. Tasarım Kuralları
- Vurgu rengi: Acrobat-benzeri kırmızı (`#E5322D`); seçim/aktif: mavi (`#2D6BE4` tonu); arka plan açık gri (`#F5F6F8`), kartlar beyaz, 1 px `#E5E7EB` kenarlık, 10 px köşe
- Sidebar genişliği ~190 px, aktif öğe açık mavi arka plan
- Sağ panel genişliği ~220 px, bölüm başlıkları kalın, ikon + etiket satırları
- Tipografi: SF Pro (sistem), başlık 22 pt semibold, kart başlığı 13 pt semibold, açıklama 11 pt gri
- İkonlar: SF Symbols (ekran görüntüsündeki ikonlara en yakın olanlar)
- Türkçe metinler ekran görüntüsündekiyle **birebir aynı**

---

## 5. Kabul Kriterleri (tam sürüm sayılması için)
1. `./build.sh` hatasız tamamlanır, `.app` açılır
2. 15 aracın tamamı çalışır (Faz 3 dönüştürmeler en azından metin + görsel düzeyinde)
3. 100 MB / 500 sayfalık PDF donmadan açılır ve kaydırılır
4. Tüm değişiklikler geri alınabilir, kaydetmeden kapatmada uyarı çıkar
5. Finder'da PDF'e çift tıklayınca Qeniro PDF ile açılabilir
6. Arayüz Türkçe, ekran görüntüsüyle tutarlı; koyu tema desteklenir

---

## 6. Bilinen Sınırlar (kullanıcıya dürüstçe belirtilecek)
- PDF'teki **mevcut metni doğrudan düzenleme** (Acrobat gibi) PDFKit'te yoktur; üstünü örtüp yeniden yazma yaklaşımı kullanılacak
- Office dönüştürme %100 düzen sadakati vermez; metin/görsel/tablo korunur
- Sertifika ile imza için Keychain'de bir kimlik sertifikası olmalı
- App Store / notarization ücretli geliştirici hesabı ister; şimdilik yerel `.app`

---

## 7. Opus'a Çalışma Talimatı
- Bu klasörde (`~/Desktop/Projeler/Qeniro Pdf`) çalış; kullanıcıya soru sormadan ilerle ("sen devam et sorma").
- Faz sırasına uy; her fazın sonunda derlenebilir durum bırak, `PROGRESS.md`'de işaretle.
- Xcode çalıştıramıyorsan: kodu yaz, `build.sh` hazırla; mümkünse bilgisayar kontrolüyle Xcode'da derleyip hataları düzelt.
- Kullanıcıya Türkçe, kısa ve net rapor ver; bitince özellik durumu tablosunu paylaş.
