#!/bin/bash
# Qeniro PDF derleme betiği
# Kullanım:  ./build.sh          -> Debug derle
#            ./build.sh run      -> Debug derle ve uygulamayı aç
#            ./build.sh test     -> birim testlerini çalıştır
#            ./build.sh release  -> Release derle, build/Qeniro PDF.app oluşturur
set -euo pipefail
cd "$(dirname "$0")"

if ! command -v xcodebuild >/dev/null 2>&1; then
  echo "HATA: xcodebuild bulunamadı. App Store'dan Xcode'u kurun ve bir kez açın."
  echo "      Sonra: sudo xcode-select -s /Applications/Xcode.app"
  exit 1
fi

if ! command -v xcodegen >/dev/null 2>&1; then
  if command -v brew >/dev/null 2>&1; then
    echo "xcodegen bulunamadı, Homebrew ile kuruluyor…"
    brew install xcodegen
  else
    echo "HATA: xcodegen yok. Önce Homebrew kurun (https://brew.sh) ve 'brew install xcodegen' çalıştırın."
    exit 1
  fi
fi

# --- PDFium (gerçek metin düzenleme için) ---------------------------------
# bblanchon/pdfium-binaries sürümü sabitlenmiştir. Klasör yoksa indirilir.
PDFIUM_VERSION="8057"
PDFIUM_DIR="Vendor/pdfium"
PDFIUM_LIB="$PDFIUM_DIR/lib/libpdfium.dylib"
if [ ! -f "$PDFIUM_LIB" ] || [ ! -f "$PDFIUM_DIR/include/fpdfview.h" ]; then
  echo "==> PDFium indiriliyor (chromium/$PDFIUM_VERSION, macOS universal)"
  mkdir -p "$PDFIUM_DIR"
  PDFIUM_TMP="$(mktemp -d)"
  if ! curl -fL --retry 3 -o "$PDFIUM_TMP/pdfium.tgz" \
      "https://github.com/bblanchon/pdfium-binaries/releases/download/chromium%2F${PDFIUM_VERSION}/pdfium-mac-univ.tgz"; then
    echo "HATA: PDFium indirilemedi. İnternet bağlantınızı kontrol edip tekrar deneyin."
    exit 1
  fi
  tar -xzf "$PDFIUM_TMP/pdfium.tgz" -C "$PDFIUM_DIR"
  rm -rf "$PDFIUM_TMP"
fi
# Kitaplığın kimliği @rpath olmalı; uygulama onu Contents/Frameworks içinden yükler.
PDFIUM_ID="$(otool -D "$PDFIUM_LIB" | tail -n 1)"
if [ "$PDFIUM_ID" != "@rpath/libpdfium.dylib" ]; then
  echo "==> PDFium kimliği @rpath olarak ayarlanıyor"
  install_name_tool -id "@rpath/libpdfium.dylib" "$PDFIUM_LIB"
  codesign --force --sign - "$PDFIUM_LIB" >/dev/null 2>&1 || true
fi
xattr -cr Vendor 2>/dev/null || true

echo "==> Xcode projesi oluşturuluyor (xcodegen generate)"
xcodegen generate --spec project.yml

MODE="${1:-debug}"
# Masaüstü/iCloud eşitlemesi dosyalara ek öznitelik ekleyip imzalamayı bozduğu için
# derleme çıktısı Masaüstü dışında tutulur.
DERIVED="$HOME/Library/Developer/QeniroPDF/DerivedData"
LOG="build/build.log"
mkdir -p build "$DERIVED"
# Derleme kopyaları Spotlight/Launchpad'de ayrı uygulama olarak görünmesin.
touch "$DERIVED/.metadata_never_index"

case "$MODE" in
  test)
    echo "==> Testler çalıştırılıyor"
    xcodebuild -project QeniroPDF.xcodeproj -scheme QeniroPDF -configuration Debug \
      -derivedDataPath "$DERIVED" test 2>&1 | tee "$LOG" | grep -E "error:|warning: unre|Test Suite|Executed|passed|failed" || true
    exit "${PIPESTATUS[0]}"
    ;;
  release)
    CONFIG=Release ;;
  *)
    CONFIG=Debug ;;
esac

echo "==> Ek dosya öznitelikleri temizleniyor"
xattr -cr QeniroPDF Config 2>/dev/null || true

echo "==> Derleniyor ($CONFIG)"
set +e
xcodebuild -project QeniroPDF.xcodeproj -scheme QeniroPDF -configuration "$CONFIG" \
  -derivedDataPath "$DERIVED" build > "$LOG" 2>&1
STATUS=$?
set -e

if [ $STATUS -ne 0 ]; then
  echo "DERLEME BAŞARISIZ. Hatalar:"
  grep -E "error:|failed|not allowed" "$LOG" | sort -u | head -50 || true
  echo "Tam günlük: $LOG"
  exit $STATUS
fi

APP="$DERIVED/Build/Products/$CONFIG/Qeniro PDF.app"
# PDFium uygulama paketine gömülmemişse elle ekle ve yeniden imzala.
if [ ! -f "$APP/Contents/Frameworks/libpdfium.dylib" ]; then
  echo "==> PDFium uygulama paketine ekleniyor"
  mkdir -p "$APP/Contents/Frameworks"
  cp "$PDFIUM_LIB" "$APP/Contents/Frameworks/"
  codesign --force --sign - "$APP/Contents/Frameworks/libpdfium.dylib"
  codesign --force --sign - --entitlements Config/QeniroPDF.entitlements "$APP"
fi
echo "==> Derleme başarılı: $APP"
if [ "$CONFIG" = "Release" ]; then
  rm -rf "build/Qeniro PDF.app"
  ditto --noextattr --norsrc "$APP" "build/Qeniro PDF.app"
  echo "==> Uygulama kopyalandı: build/Qeniro PDF.app  (Uygulamalar klasörüne sürükleyebilirsiniz)"
fi
if [ "$MODE" = "run" ]; then
  open "$APP"
fi
