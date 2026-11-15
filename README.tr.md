# Qeniro PDF (macOS)

Swift + SwiftUI + PDFKit + Vision + PDFium ile yazılmış, macOS 14 (Sonoma) ve üstü için native PDF uygulaması.
Arayüz tamamen Türkçedir; açık ve koyu temayı destekler.

## Kurulum ve derleme

Gerekenler:

1. **Xcode 16 veya üstü** (App Store). Bir kez açıp lisansı kabul edin.
2. **XcodeGen**: `brew install xcodegen` (Homebrew yoksa: https://brew.sh). `build.sh` bunu kendisi kurmayı dener.
3. **İnternet bağlantısı (yalnızca ilk derlemede)**: `build.sh`, gerçek metin düzenleme için gereken PDFium kitaplığını
   (`bblanchon/pdfium-binaries`, sürüm `chromium/8057`, macOS universal) `Vendor/pdfium` klasörüne indirir.

Terminal'de:

```bash
cd ~/Desktop/Projeler/"Qeniro Pdf"
./build.sh run        # derler ve uygulamayı açar
./build.sh release    # build/Qeniro PDF.app oluşturur (Uygulamalar klasörüne sürükleyin)
./build.sh test       # birim testleri
```

Xcode ile çalışmak isterseniz: önce bir kez `./build.sh` (PDFium'u indirir), sonra `xcodegen generate` ve `QeniroPDF.xcodeproj` ile ⌘R.

Uygulama yerel olarak imzalanır (ad-hoc, "-"). İlk açılışta macOS uyarı verirse uygulamaya sağ tıklayın > Aç.
Finder'da PDF'leri Qeniro PDF ile açmak için: PDF'ye sağ tıklayın > Bilgi Al > Birlikte Aç > Qeniro PDF > Tümünü Değiştir.

## Belge görüntüleyici düzeni

Açık bir PDF'de üstte dört sekme vardır: **Tüm araçlar · Düzenle · Dönüştür · E-imza**. Solda 300 pt genişliğinde
araç paneli seçili sekmeye göre değişir (✕ veya sağ üstteki kenar çubuğu düğmesiyle kapanır/açılır). Sayfa alanının
solunda yüzen dikey araç çubuğu bulunur: **Seç**, **Yorum** (yapışkan not), **Vurgula**, **Çiz** (serbest çizim) ve
**•••** (altını çiz, üstünü çiz, dikdörtgen, elips, çizim rengi).

- **Tüm araçlar:** PDF olarak dışa aktar, PDF Düzenle, E-imza iste, Doldur ve İmzala, PDF oluştur, Dosyaları birleştir,
  Sayfaları organize et, Yorum için gönder (macOS paylaşım menüsü), Tarama ve OCR, PDF koru, PDF'yi redakte et,
  PDF sıkıştır, Form hazırla, Yorum ekleyin; "Daha fazla göster" ile böl, Word/Excel/PowerPoint, sertifika ile imza,
  imzaları doğrula, hassas bilgileri kaldır, üstbilgi/altbilgi, filigran.
- **Düzenle:** sayfayı döndür, kırp (sürükleyerek kırpma kutusu), sil, çıkar (yeni PDF), sayfaları organize et;
  **Metin** (PDF içindeki gerçek metni değiştirme ve yeni gerçek metin ekleme), görüntü, üstbilgi ve altbilgi
  (metin + sayfa numarası, tüm sayfalara), filigran (metin, opaklık, açı), bağlantı (web adresi veya sayfa numarası);
  dosyaları birleştir, redaksiyon, form hazırla (metin alanı, onay kutusu, radyo, açılır liste, imza alanı).
- **Dönüştür:** Word (DOCX), PowerPoint (PPTX), Excel (XLSX), görüntü (JPEG/PNG/TIFF), diğer (RTF/TXT/HTML);
  tanınan metin dili (Türkçe varsayılan); PDF'ye dönüştür, sıkıştır, Tara ve OCR Uygula.
- **E-imza:** imza ekle, baş harfleri, metin, onay kutusu, radyo düğmesi, tarih, **Uygula**; imza alanı ekle;
  sertifika ile imzala; imzaları doğrula. Belgede gerçekten dijital imza varsa ve en az biri doğrulanamıyorsa
  sayfanın üstünde mavi "En az bir imzada sorun var." bandı görünür.

## Gerçek metin düzenleme (PDFium)

Düzenle sekmesinde **Metin** aracı seçiliyken sayfadaki yazıların üzerine gelince ince kesikli mavi çerçeve görünür.
Yazıya tıklayınca yerinde bir düzenleme kutusu açılır; **Enter** veya kutunun dışına tıklamak değişikliği uygular,
**Esc** vazgeçer. Kaydedince PDF'in içindeki asıl metin değişir (üstü beyaz kutuyla örtülmez).

- Mümkünse metin **aynı metin nesnesinde, özgün yazı tipiyle** değiştirilir.
- PDF'e gömülü yazı tipi yalnızca belgede kullanılan karakterleri içerir (alt küme). Yeni karakterler (ör. ğ, ş, ı, İ)
  bu alt kümede yoksa o satır silinir ve **aynı konum, boyut ve renkte** benzer bir sistem yazı tipiyle
  (Arial, Times New Roman, Courier New, Georgia, Verdana… `/System/Library/Fonts/Supplemental`) yeniden yazılır.
- Soldaki panelden yazı tipi, boyut, kalın/italik/altı çizili, renk ve hizalama seçili satıra uygulanır.
- Boş bir yere tıklayıp yazmak sayfaya **gerçek metin nesnesi** ekler. Seçili satırı ⌫ ile silebilirsiniz.
- Üstbilgi/altbilgi ve filigran da sayfa içeriğine gerçek metin olarak eklenir. Tüm işlemler ⌘Z ile geri alınabilir.
- Şifreli PDF'ler açılırken girilen şifreyle düzenlenir.
- Eski "üstünü örtüp yeniden yaz" yöntemi Düzenle > Diğer altında yedek olarak durur.

## Özellik durumu

| Alan | Özellik | Durum |
|---|---|---|
| Kabuk | Kenar çubuğu (Ana Sayfa, Araçlar, Son Dosyalar, Yıldızlı, Bulut Depolama), sekmeler, Yardım/Bildirim/Hesap | Tamam |
| Ana Sayfa | 8 hızlı araç kartı, Son Dosyalar (boyut, tarih, ⋮ menüsü) | Tamam |
| Görüntüleyici | Sekmeler (Tüm araçlar, Düzenle, Dönüştür, E-imza), sol araç paneli, yüzen araç çubuğu | Tamam |
| Görüntüleyici | Aç, sayfa gezinme, yakınlaştırma, döndürme, el ve seçim aracı, arama, yazdırma, kaydet, küçük resimler, şifreli PDF, geri al/yinele | Tamam |
| Yorumlar | Yapışkan not, vurgula, altını/üstünü çiz, serbest çizim, dikdörtgen/elips | Tamam |
| PDF Düzenle | Mevcut metni gerçekten değiştirme ve yeni gerçek metin ekleme (PDFium) | Tamam |
| PDF Düzenle | Görsel, bağlantı, üstbilgi/altbilgi, filigran, sayfa kırpma | Tamam |
| İmzala ve Doldur | İmza çiz/yaz/görselden, baş harfler, metin, onay kutusu, radyo, tarih, **Uygula** ile düzleştirme | Tamam |
| Form hazırla | Metin alanı, onay kutusu, radyo düğmesi, açılır liste, imza alanı | Tamam |
| Sertifika ile İmzala | Anahtar Zinciri sertifikasıyla PAdES (adbe.pkcs7.detached, SHA-256) | Tamam (sertifika gerekir) |
| İmzaları doğrula | PDFium ile imza okuma, CMS + sertifika güveni (Security çerçevesi), uyarı bandı | Tamam |
| Birleştir / Böl / Sayfaları Düzenle / Sıkıştır / Koruma / Sansürle / Hassas Bilgileri Kaldır | | Tamam |
| PDF Oluştur | Görsellerden, Word/RTF/ODT/HTML/metinden, boş sayfa, panodan; LibreOffice varsa Excel/PowerPoint/iWork | Tamam |
| OCR | Vision ile aranabilir PDF, tanınan dil seçilebilir (Türkçe varsayılan) | Tamam |
| Dönüştür | DOCX, XLSX, PPTX, JPEG/PNG/TIFF, RTF/TXT/HTML, aranabilir PDF | Tamam (metin düzeyinde) |
| Yorum için gönder | Yorumlu PDF'i macOS paylaşım menüsüyle gönderme | Tamam |
| Bulut Depolama | iCloud Drive ve ~/Library/CloudStorage içindeki PDF'ler | Tamam |
| PDF/A | Arşiv standardında çıktı | Yok |

## Teknik kararlar

- **XcodeGen**: `.xcodeproj` elle yazılmaz; `project.yml`'den üretilir.
- **PDFium**: Gerçek metin düzenleme, üstbilgi/altbilgi, filigran ve imza okuma için Google'ın PDFium kitaplığı kullanılır
  (`bblanchon/pdfium-binaries` hazır derlemesi). `build.sh` kitaplığı indirir, kimliğini `@rpath/libpdfium.dylib`
  yapar; Xcode onu uygulama paketinin `Contents/Frameworks` klasörüne gömer. Swift'e
  `QeniroPDF/PDFium/QeniroPDF-Bridging-Header.h` köprü başlığıyla açılır. Hizmet: `Services/PDFiumEditor.swift`.
- **Görüntüleme PDFKit'te kalır**: PDFium ile yapılan her düzenlemeden sonra belge PDFKit'e yeniden yüklenir;
  sayfa ve yakınlaştırma korunur, önceki belge geri alma yığınına konur.
- **Sandbox kapalı**: iCloud Drive/CloudStorage klasörleri listelenebilir ve isteğe bağlı LibreOffice çalıştırılabilir.
- **Office dönüştürme**: saf Swift OpenXML yazıcı ve bağımlılıksız ZIP yazıcı; LibreOffice kuruluysa isteğe bağlı.
- **Görsel ve imzalar** PDFKit'te özel çizimli açıklama olarak tutulur; kaydederken sayfaya gömülür.

## Lisanslar

- **PDFium**: BSD 3-Clause ve Apache 2.0 lisansları (© The PDFium Authors; metin `Vendor/pdfium/licenses/pdfium.txt`).
  Hazır derleme `bblanchon/pdfium-binaries` (MIT) üzerinden alınır. PDFium'un içerdiği üçüncü taraf bileşenlerin (FreeType, libjpeg-turbo, OpenJPEG,
  zlib, lcms, ICU vb.) lisans metinleri `Vendor/pdfium/licenses/` klasöründedir. Dağıtırken bu metinleri uygulamayla
  birlikte verin.

## Bilinen sınırlar

- **Alt küme yazı tipleri:** Yeni karakterler PDF'e gömülü yazı tipinde yoksa o satır benzer bir sistem yazı tipine
  geçer (görünüm çok yakın ama birebir aynı olmayabilir). Sistem yazı tipi tüm dosyasıyla gömüldüğü için dosya
  boyutu yazı tipi başına birkaç yüz KB artabilir.
- **Satır düzeyinde düzenleme:** Her satır ayrı düzenlenir; paragraf içinde satırlar yeniden akmaz. Aynı satırdaki
  farklı yazı tipli parçalar ayrı öğe olarak görünür. Form XObject içine yerleştirilmiş metinler (bazı tasarım
  programlarının çıktıları) düzenlenemez; bunlar için Düzenle > Diğer > "Seçili metni örtüp yeniden yaz" yedeğini
  kullanın.
- **Taranmış sayfalar** düzenlenebilir metin içermez; uygulama bunu bildirir. Tara ve OCR Uygula aranabilir (görünmez)
  metin katmanı ekler, görüntüdeki yazıyı değiştirmez.
- **Altı çizili** biçimi gerçek metne tek yönlü (ince çizgi olarak) eklenir; kaldırmak için ⌘Z kullanın.
- **Office dönüştürmeleri %100 düzen sadakati vermez.** Daha yüksek sadakat için ücretsiz LibreOffice'i kurabilirsiniz.
- **Sertifika ile imza** için Anahtar Zinciri'nde özel anahtarı olan bir kimlik sertifikası gerekir. İmzalı bir
  belgeyi düzenleyip kaydetmek mevcut imzaları geçersiz kılar.
- **İmza doğrulama** macOS güven ayarlarını kullanır; kendinden imzalı veya tanınmayan kök sertifikalar "sorun var"
  olarak gösterilir. Yalnızca CMS (adbe.pkcs7.detached / ETSI.CAdES.detached) imzalar doğrulanır.
- **Sansür ve sıkıştırmadaki "görüntüye çevir"** seçenekleri o sayfaları görüntüye dönüştürür.
- **App Store ve notarization** ücretli Apple Developer hesabı gerektirir. PDF/A çıktısı desteklenmez.

## Klasör yapısı

```
project.yml, build.sh, Config/ (Info.plist, entitlements)
Vendor/pdfium/  build.sh tarafından indirilir (include/, lib/libpdfium.dylib, licenses/)
QeniroPDF/
  App/        @main, AppDelegate, menüler, AppState
  Models/     DocumentSession (sekme durumu, geri alma, metin düzenleme), ToolKind, FileLibrary, SignatureStore, TextStyle
  PDFium/     Köprü başlığı
  Services/   PDFiumEditor, SignatureVerifier, Birleştir, Böl, Sıkıştır, Koruma, Temizle, OCR, Oluştur, Dönüştür, OpenXML, ZIP, Sertifika imzası, Bulut
  Views/      Shell, Home, Tools, Viewer (QPDFView, sekmeler, yüzen araç çubuğu), Panels (sekme panelleri), Components
  Theme/      Renkler ve tipografi
  Resources/  Assets.xcassets (uygulama simgesi)
QeniroPDFTests/  Servis birim testleri
preview/      Faz 0 HTML görsel önizlemesi
```


# Qeniro PDF (iPhone, iOS 17+)

`iOS/` klasöründe aynı uygulamanın iPhone sürümü vardır (SwiftUI + PDFKit + Vision + VisionKit + PencilKit + PDFium).
macOS projesinden bağımsız bir XcodeGen projesidir (`iOS/project.yml`, hedef `QeniroPDFiOS`, paket kimliği
`com.qeniro.pdf.ios`). Platformdan bağımsız dosyalar macOS kaynaklarından doğrudan paylaşılır:
`QeniroPDF/Services/ZipWriter.swift`, `OfficeExportService.swift`, `PDFOCRService.swift`,
`QeniroPDF/Utilities/Formatters.swift`. AppKit'e bağlı servislerin (PDFKit yardımcıları, PDFium düzenleyici,
birleştir/böl/sıkıştır/koru/temizle, dönüştür) UIKit karşılıkları `iOS/QeniroPDFiOS/Services/` altındadır.

## Derleme

Gerekenler: Xcode 16+ ve **Xcode'da iOS platformu** (Xcode > Settings > Components > iOS > Get), XcodeGen
(`brew install xcodegen`), ilk derlemede internet (PDFium indirilir).

- **Simülatör:** proje kökündeki **`iPhone Derle.command`** dosyasına çift tıklayın (çıktı `build/ios-derle.txt`).
  Terminalden: `./iOS/build-ios.sh` (yalnızca derler) veya `./iOS/build-ios.sh run` (derler, iPhone simülatörünü açıp kurar).
- **Kendi iPhone'unuza kurulum:** iPhone'u kabloyla bağlayın, kilidini açın, "Bu bilgisayara güven" deyin ve
  iPhone'da Ayarlar > Gizlilik ve Güvenlik > **Geliştirici Modu**'nu açın. Xcode > Settings > Accounts bölümünde
  geliştirici Apple kimliğinizle oturum açın. Sonra:
  `DEVELOPMENT_TEAM=TAKIMKIMLIGI ./iOS/build-ios.sh device`
  (Takım kimliği: developer.apple.com > Account > Membership, 10 karakter). Betik imzalı derler, `xcrun devicectl`
  ile kurar ve açar. Xcode ile çalışmak isterseniz: `iOS/QeniroPDFiOS.xcodeproj` > hedef QeniroPDFiOS >
  Signing & Capabilities > Team seçin > iPhone'unuzu seçip ⌘R.
- Derleme çıktısı Masaüstü dışında, `~/Library/Developer/QeniroPDF-iOS/DerivedData` altındadır (Spotlight dizinlemez).

## PDFium (iOS)

`build-ios.sh`, macOS sürümüyle aynı PDFium derlemesini (`bblanchon/pdfium-binaries`, `chromium/8057`) iOS için
indirir: `pdfium-ios-device-arm64`, `pdfium-ios-simulator-arm64` ve `pdfium-ios-simulator-x64` (son ikisi `lipo` ile
birleşir). Bu paketler dinamik kitaplık (`libpdfium.dylib`, iOS 17 alt sınırı) içerir; betik her birini
`pdfium.framework` olarak sarar (`@rpath/pdfium.framework/pdfium`) ve `xcodebuild -create-xcframework` ile
`Vendor/pdfium-ios/pdfium.xcframework` üretir. Xcode onu uygulamaya gömer ve imzalar (Embed & Sign).
İndirme başarısız olursa uygulama yine derlenir (`QPDF_PDFIUM` bayrağı kapalı) ama Düzenle > Metin gerçek metin
düzenleme yerine "PDFium yok" uyarısı verir.

**iOS'ta yazı tipleri:** iOS'ta `/System/Library/Fonts/Supplemental` yoktur. Yeni karakterler (ğ, ş, ı, İ) PDF'e
gömülü alt küme yazı tipinde yoksa satır, iOS'ta yüklü benzer yazı tipiyle (Arial, Times New Roman, Courier New,
Georgia, Verdana, Trebuchet MS, Helvetica…) yeniden yazılır; yazı tipi Core Text tablolarından bellekte TrueType
dosyası olarak kurulup PDFium'a verilir.

## iPhone ekranları

- **Ana Sayfa:** logo + "Qeniro PDF", Hoş Geldiniz, dosya/araç arama, 8 hızlı araç, **Belge Tara** (VisionKit
  kamera tarayıcı → PDF + Vision OCR ile aranabilir görünmez metin; `Dosyalar > iPhone'umda > Qeniro PDF` klasörüne
  kaydedilir), Son Dosyalar, sağ altta **+** (Dosyalar'dan PDF aç). Alt sekmeler: Ana Sayfa · Araçlar · Dosyalar · Yıldızlı.
- **Görüntüleyici:** üst çubuk (geri, ad, sayfa x/y, ara, paylaş), yüzen araç çubuğu (Seç, Yorum, Vurgula, Çiz,
  ••• altını/üstünü çiz, çizim rengi, geri al/yinele, sil, yıldızla, döndür), alt sekmeler **Tüm araçlar · Düzenle ·
  Dönüştür · E-imza**; her biri alttan açılan panel (orta/büyük; küçük konumda sayfa kullanılabilir kalır).
- **Düzenle:** yazıya dokun → yerinde düzenleme kutusu; Bitti/dışarı dokunmak uygular, **Kaydet** PDF'teki asıl metni
  değiştirir. Yazı tipi, boyut, B, I, renk, altı çizili; İçerik ekle (Metin, Görüntü, Üst/Alt bilgi, Filigran,
  Bağlantı); Sayfayı değiştir (döndür, kırp, sil, sayfaları organize et: sürükle-bırak, döndür, sil, çıkar).
  Üstte **Vazgeç** moda girdikten sonraki değişiklikleri geri alır.
- **Dönüştür:** Word, PowerPoint, Excel, görüntü (JPEG/PNG), diğer (RTF/TXT/HTML); tanınan metin dili (Türkçe
  varsayılan); düğme seçime göre "DOCX'e Dönüştür" vb.; sonuç paylaşım menüsüyle (Dosyalara Kaydet dahil).
- **E-imza:** Çiz (parmak/Apple Pencil, PencilKit), Yaz (el yazısı yazı tipleri), Görsel (fotoğraftan, beyazı
  kaldırma); baş harfler, metin, onay, tarih; imzalar uygulama içinde saklanır; **İmzayı Kaydet ve Yerleştir**,
  sürükleyerek taşıma, büyüt/küçült; **Uygula** öğeleri sayfaya gömer.
- **Araçlar:** PDF oluştur (tarama, fotoğraflar, metin/RTF/HTML, boş), birleştir, böl, sıkıştır, şifreyle koru,
  sansürle, hassas bilgileri kaldır, OCR, Word/Excel/PowerPoint'e dönüştür.
- **Dosyalar uygulaması:** PDF'ler yerinde açılır ve kaydedilir (`LSSupportsOpeningDocumentsInPlace`,
  `UISupportsDocumentBrowser`); "Paylaş > Qeniro PDF" ile açılabilir. Kaydetmeden çıkarken uyarı verir.
  Geri al/yinele, karanlık mod desteklenir.

## iOS sınırları

- Word (.docx) dosyasından PDF oluşturma iPhone'da yok (metin, RTF, HTML var). Sertifika ile dijital imza ve
  imza doğrulama yalnızca Mac sürümündedir. Sıkıştırma Quartz filtresi yerine PDFKit'in JPEG/ekran
  çözünürlüğü seçeneklerini veya "görüntüye çevir" seçeneğini kullanır.
- Derleme bu oturumda (Linux, derleyicisiz) yapılamadı; Mac'te `iPhone Derle.command` ile doğrulanmalıdır.
