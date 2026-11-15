# Qeniro PDF — İlerleme

Son güncelleme: 2026-11-06

| Faz | Kapsam | Durum |
|---|---|---|
| Faz 0 | 4 ekranın macOS görünümlü HTML önizlemesi (açık + koyu): `preview/index.html` | Tamamlandı |
| Faz 1 | project.yml, build.sh, Info.plist (PDF ilişkilendirme), kabuk, Ana Sayfa, Tüm Araçlar, görüntüleyici, Son Dosyalar, Yıldızlı, Bulut Depolama | Tamamlandı (Mac'te derlendi) |
| Faz 2 | PDF Düzenle, İmzala ve Doldur, Sertifika ile İmzala, Birleştir, Böl, Sayfaları Düzenle, Sıkıştır, Koruma, Sansürle, Hassas Bilgileri Kaldır, PDF Oluştur, geri al/yinele, kısayollar | Tamamlandı (Mac'te derlendi) |
| Faz 3 | OCR (Vision), PDF → Word/Excel/PowerPoint, PDF → görüntü/TXT/RTF, aranabilir PDF, toplu işlem, LibreOffice köprüsü | Tamamlandı (Mac'te derlendi) |
| Faz 4 | Özgün simge, koyu tema, pencere boyutu hatırlama, hata yakalama, birim testleri, README | Tamamlandı (Mac'te derlendi) |
| Faz 5 | Acrobat düzeni: Tüm araçlar · Düzenle · Dönüştür · E-imza sekmeleri, 300 pt sol araç paneli, yüzen araç çubuğu (Seç, Yorum, Vurgula, Çiz, •••) | Kod tamamlandı, Mac'te derlenecek |
| Faz 5 | PDFium ile gerçek metin düzenleme (yerinde değiştirme, yazı tipi yedeği, yeni metin), üstbilgi/altbilgi, filigran, kırpma, form hazırla (açılır liste, imza alanı), yorum için gönder, imza doğrulama ve uyarı bandı, Dönüştür paneli (TIFF, HTML, OCR dili) | Kod tamamlandı, Mac'te derlenecek |

## Doğrulama

- Faz 1-4 kodu Mac'te hatasız derlendi (2026-11-06).
- Faz 5 kodu derleyici olmayan bir Linux ortamında yazıldı; PDFium başlıkları (chromium/8057) ve Apple API'leri
  belgelere göre kontrol edildi. **Mac'te derleme gerekli:** `./build.sh run` (ilk çalıştırmada PDFium indirilir).
  Hata çıkarsa `build/build.log` dosyasındaki `error:` satırlarını Claude'a iletin.
- Birim testleri: `./build.sh test`.

## Kabul kriterleri kontrol listesi

- [x] `./build.sh` hatasız tamamlanır (Faz 1-4)
- [ ] Faz 5 ile `./build.sh run` hatasız tamamlanır, PDFium uygulama paketine gömülür
- [ ] Düzenle > Metin: bir yazıya tıklayıp değiştirince kaydedilen dosyada metin gerçekten değişir (başka bir PDF okuyucuda kontrol)
- [ ] Türkçe karakter (ğ, ş, ı, İ) eklenince satır benzer sistem yazı tipine geçer ve doğru görünür
- [x] Değişiklikler geri alınabilir; kaydetmeden kapatmada uyarı
- [x] Türkçe arayüz, koyu tema

Özellik ayrıntıları ve bilinen sınırlar için `README.md` dosyasına bakın.


## iPhone (iOS 17+) sürümü — durum

Son güncelleme: 2026-11-08. Kod derleyicisi olmayan bir Linux ortamında yazıldı; Apple API'leri belgelere göre
kontrol edildi. **Mac'te derlenmesi gerekiyor:** `iPhone Derle.command` (hata olursa `build/ios-derle.txt`).

| Alan | Kapsam | Durum |
|---|---|---|
| Proje | `iOS/project.yml` (XcodeGen, QeniroPDFiOS, iOS 17, com.qeniro.pdf.ios), `iOS/pdfium.yml`, Info.plist (PDF belge türü, Dosyalar'da yerinde açma, Türkçe kamera izni), AppIcon 1024 | Kod tamamlandı, Mac'te derlenecek |
| Derleme | `iOS/build-ios.sh` (simülatör, `run`, `device` + devicectl kurulum), `iPhone Derle.command` | Kod tamamlandı, Mac'te denenecek |
| PDFium iOS | chromium/8057 cihaz arm64 + simülatör arm64/x64 → pdfium.xcframework (dinamik, Embed & Sign); PDFium yoksa yedek yol | Kod tamamlandı, Mac'te denenecek |
| Paylaşılan kod | ZipWriter, OfficeExportService, PDFOCRService, Formatters (macOS dosyaları; OfficeExport/OCR'ye `#if os(macOS)` eklendi, macOS davranışı aynı) | Tamam (macOS yeniden derlenip doğrulanmalı) |
| Ana Sayfa | Logo, Hoş Geldiniz, arama, 8 hızlı araç, Belge Tara (VisionKit + OCR), Son Dosyalar, + ile dosya aç, 4 sekme | Kod tamamlandı |
| Görüntüleyici | PDFView, üst çubuk, arama, paylaş, yüzen araç çubuğu (Seç, Yorum, Vurgula, Çiz, •••), alt sekmeler + alt paneller | Kod tamamlandı |
| Düzenle | PDFium ile gerçek metin düzenleme (yerinde kutu), yazı tipi/boyut/B/I/renk, metin/görüntü/üst-alt bilgi/filigran/bağlantı, döndür/kırp/sil/organize et | Kod tamamlandı |
| Dönüştür | DOCX, PPTX, XLSX, JPEG/PNG, RTF/TXT/HTML, OCR dili, paylaşım | Kod tamamlandı |
| E-imza | Çiz (PencilKit)/Yaz/Görsel, baş harfler, metin, onay, tarih, kayıtlı imzalar, yerleştir + sürükle, Uygula | Kod tamamlandı |
| Araçlar | Oluştur, birleştir, böl, sıkıştır, şifreyle koru, sansürle, hassas bilgileri kaldır, OCR | Kod tamamlandı |
| Genel | Kaydetmeden çıkış uyarısı, geri al/yinele, karanlık mod, Dosyalar ile entegrasyon | Kod tamamlandı |

### iPhone kabul kriterleri

- [ ] `iPhone Derle.command` hatasız biter
- [ ] Simülatörde bir PDF açılır, Düzenle > yazıya dokunup değiştirince kaydedilen dosyada metin gerçekten değişir
- [ ] Türkçe karakter eklenince satır benzer iOS yazı tipine geçer ve doğru görünür
- [ ] Gerçek iPhone'da Belge Tara çalışır, taranan PDF'de metin aranabilir
- [ ] E-imza: çizilen imza kaydedilir, yerleştirilir, sürüklenir, Uygula ile gömülür
- [ ] Dosyalar uygulamasında bir PDF'yi "Paylaş > Qeniro PDF" ile açma
