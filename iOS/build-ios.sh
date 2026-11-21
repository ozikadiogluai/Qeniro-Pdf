#!/bin/bash
# Qeniro PDF — iPhone derleme betiği
# Kullanım:  ./build-ios.sh            -> iOS Simülatörü için imzasız Debug derleme
#            ./build-ios.sh run        -> simülatör derlemesi + ilk iPhone simülatörüne kurup açar
#            ./build-ios.sh device     -> bağlı iPhone için imzalı derleme ve kurulum
#                                         (DEVELOPMENT_TEAM=XXXXXXXXXX ./build-ios.sh device)
set -euo pipefail
cd "$(dirname "$0")"
IOS_DIR="$(pwd)"
ROOT="$(cd .. && pwd)"
MODE="${1:-sim}"

if ! command -v xcodebuild >/dev/null 2>&1; then
  echo "HATA: xcodebuild bulunamadı. App Store'dan Xcode'u kurun ve bir kez açın."
  echo "      Sonra: sudo xcode-select -s /Applications/Xcode.app"
  exit 1
fi

if ! xcodebuild -showsdks 2>/dev/null | grep -q "iphonesimulator"; then
  echo "HATA: Xcode'da iOS platformu yüklü değil."
  echo "      Xcode > Settings (Ayarlar) > Components (Bileşenler) > iOS satırındaki Get/İndir düğmesine basın,"
  echo "      indirme bitince bu betiği yeniden çalıştırın."
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

# --- PDFium (gerçek metin düzenleme) ----------------------------------------
# bblanchon/pdfium-binaries, macOS sürümüyle aynı: chromium/8057. iOS paketleri dinamik kitaplık
# (libpdfium.dylib) içerir; her biri pdfium.framework'e sarılır ve tek pdfium.xcframework yapılır:
#   - cihaz: ios-device-arm64
#   - simülatör: ios-simulator-arm64 + ios-simulator-x64 (lipo ile birleşik)
PDFIUM_VERSION="8057"
PDFIUM_DIR="$ROOT/Vendor/pdfium-ios"
XCF="$PDFIUM_DIR/pdfium.xcframework"
BASE_URL="https://github.com/bblanchon/pdfium-binaries/releases/download/chromium%2F${PDFIUM_VERSION}"

make_framework() {
  # $1: dylib, $2: çıktı klasörü, $3: platform (iPhoneOS | iPhoneSimulator), $4: include klasörü
  local fw="$2/pdfium.framework"
  rm -rf "$fw"
  mkdir -p "$fw/Headers"
  cp "$1" "$fw/pdfium"
  install_name_tool -id "@rpath/pdfium.framework/pdfium" "$fw/pdfium"
  cp "$4"/*.h "$fw/Headers/" 2>/dev/null || true
  cat > "$fw/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key><string>en</string>
  <key>CFBundleExecutable</key><string>pdfium</string>
  <key>CFBundleIdentifier</key><string>com.qeniro.pdfium</string>
  <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
  <key>CFBundleName</key><string>pdfium</string>
  <key>CFBundlePackageType</key><string>FMWK</string>
  <key>CFBundleShortVersionString</key><string>155.0.${PDFIUM_VERSION}</string>
  <key>CFBundleVersion</key><string>${PDFIUM_VERSION}</string>
  <key>CFBundleSupportedPlatforms</key><array><string>$3</string></array>
  <key>MinimumOSVersion</key><string>17.0</string>
</dict>
</plist>
PLIST
}

PDFIUM_OK=true
if [ ! -d "$XCF" ] || [ ! -f "$PDFIUM_DIR/include/fpdfview.h" ]; then
  echo "==> PDFium iOS indiriliyor (chromium/$PDFIUM_VERSION: cihaz arm64, simülatör arm64 + x64)"
  TMP="$(mktemp -d)"
  set +e
  curl -fL --retry 3 -o "$TMP/dev.tgz" "$BASE_URL/pdfium-ios-device-arm64.tgz" &&
  curl -fL --retry 3 -o "$TMP/sim-arm64.tgz" "$BASE_URL/pdfium-ios-simulator-arm64.tgz"
  DL=$?
  curl -fL --retry 3 -o "$TMP/sim-x64.tgz" "$BASE_URL/pdfium-ios-simulator-x64.tgz"
  DLX=$?
  set -e
  if [ $DL -ne 0 ]; then
    echo "UYARI: PDFium indirilemedi. Uygulama gerçek metin düzenleme OLMADAN derlenecek."
    echo "       İnternet bağlantısını kontrol edip betiği yeniden çalıştırın."
    PDFIUM_OK=false
  else
    mkdir -p "$TMP/dev" "$TMP/sim-arm64" "$TMP/sim-x64" "$TMP/fw-dev" "$TMP/fw-sim" "$TMP/sim"
    tar -xzf "$TMP/dev.tgz" -C "$TMP/dev"
    tar -xzf "$TMP/sim-arm64.tgz" -C "$TMP/sim-arm64"
    if [ $DLX -eq 0 ]; then
      tar -xzf "$TMP/sim-x64.tgz" -C "$TMP/sim-x64"
      lipo -create "$TMP/sim-arm64/lib/libpdfium.dylib" "$TMP/sim-x64/lib/libpdfium.dylib" -output "$TMP/sim/libpdfium.dylib"
    else
      echo "UYARI: Simülatör x64 paketi indirilemedi; yalnızca Apple Silicon (arm64) simülatörü desteklenecek."
      cp "$TMP/sim-arm64/lib/libpdfium.dylib" "$TMP/sim/libpdfium.dylib"
    fi
    rm -rf "$PDFIUM_DIR"
    mkdir -p "$PDFIUM_DIR"
    cp -R "$TMP/dev/include" "$PDFIUM_DIR/include"
    cp -R "$TMP/dev/licenses" "$PDFIUM_DIR/licenses" 2>/dev/null || true
    cp "$TMP/dev/LICENSE" "$PDFIUM_DIR/LICENSE" 2>/dev/null || true
    cp "$TMP/dev/VERSION" "$PDFIUM_DIR/VERSION" 2>/dev/null || true
    make_framework "$TMP/dev/lib/libpdfium.dylib" "$TMP/fw-dev" "iPhoneOS" "$TMP/dev/include"
    make_framework "$TMP/sim/libpdfium.dylib" "$TMP/fw-sim" "iPhoneSimulator" "$TMP/dev/include"
    echo "==> pdfium.xcframework oluşturuluyor"
    xcodebuild -create-xcframework \
      -framework "$TMP/fw-dev/pdfium.framework" \
      -framework "$TMP/fw-sim/pdfium.framework" \
      -output "$XCF" >/dev/null
  fi
  rm -rf "$TMP"
fi
xattr -cr "$ROOT/Vendor" 2>/dev/null || true

if [ "$PDFIUM_OK" = true ] && [ -d "$XCF" ]; then
  export QPDF_PDFIUM=true
else
  export QPDF_PDFIUM=false
fi

echo "==> Xcode projesi oluşturuluyor (iOS/QeniroPDFiOS.xcodeproj, PDFium: $QPDF_PDFIUM)"
xcodegen generate --spec project.yml

# Masaüstü/iCloud eşitlemesi dosyalara öznitelik ekleyip imzalamayı bozduğu için derleme çıktısı
# Masaüstü dışında tutulur; Spotlight'ın bu klasörü dizinlememesi için işaret dosyası konur.
DERIVED="$HOME/Library/Developer/QeniroPDF-iOS/DerivedData"
mkdir -p "$DERIVED"
touch "$HOME/Library/Developer/QeniroPDF-iOS/.metadata_never_index" "$DERIVED/.metadata_never_index"
mkdir -p "$ROOT/build"
LOG="$ROOT/build/ios-build.log"
xattr -cr QeniroPDFiOS ../QeniroPDF/Services ../QeniroPDF/Utilities 2>/dev/null || true

show_errors() {
  echo "DERLEME BAŞARISIZ. Hatalar:"
  grep -E "error:|failed|not allowed|requires a development team|No profiles|No Account" "$LOG" | sort -u | head -60 || true
  echo "Tam günlük: $LOG"
}

case "$MODE" in
  device)
    TEAM="${DEVELOPMENT_TEAM:-}"
    if [ -z "$TEAM" ]; then
      echo "HATA: Cihaza kurmak için Apple geliştirici Takım Kimliği gerekli."
      echo "      Takım kimliğinizi developer.apple.com > Account > Membership details bölümünde bulursunuz (10 karakter)."
      echo "      Örnek:  DEVELOPMENT_TEAM=AB12CD34EF ./build-ios.sh device"
      echo "      Ayrıca Xcode > Settings > Accounts bölümünde Apple kimliğinizle oturum açmış olmalısınız."
      exit 1
    fi
    echo "==> Bağlı iPhone aranıyor"
    DEVJSON="$(mktemp)"
    xcrun devicectl list devices --json-output "$DEVJSON" >/dev/null 2>&1 || true
    DEVICE_UDID="${DEVICE:-}"
    if [ -z "$DEVICE_UDID" ]; then
      echo "--- Bulunan cihazlar ---"
      /usr/bin/python3 - "$DEVJSON" <<'PY' 2>/dev/null || true
import json, sys
try: data = json.load(open(sys.argv[1]))
except Exception: sys.exit(0)
for d in data.get("result", {}).get("devices", []):
    hw = d.get("hardwareProperties", {}); cp = d.get("connectionProperties", {}); dp = d.get("deviceProperties", {})
    print(" -", dp.get("name"), "|", hw.get("deviceType"), hw.get("platform"), "| udid:", hw.get("udid"), "| id:", d.get("identifier"),
          "| eşleşme:", cp.get("pairingState"), "| bağlantı:", cp.get("transportType"), cp.get("tunnelState"),
          "| geliştirici modu:", dp.get("developerModeStatus"))
PY
      DEVICE_UDID="$(/usr/bin/python3 - "$DEVJSON" <<'PY' 2>/dev/null || true
import json, sys
try:
    data = json.load(open(sys.argv[1]))
except Exception:
    sys.exit(0)
best = None; score_best = -1
for d in data.get("result", {}).get("devices", []):
    hw = d.get("hardwareProperties", {}); cp = d.get("connectionProperties", {}); dp = d.get("deviceProperties", {})
    if hw.get("platform") != "iOS" or hw.get("deviceType") not in ("iPhone", "iPad"):
        continue
    if cp.get("pairingState") != "paired":
        continue
    if cp.get("transportType") == "sameMachine":
        continue  # simülatör; gerçek cihaz değil
    score = 0
    if cp.get("transportType") == "wired": score += 4
    if cp.get("tunnelState") == "connected": score += 2
    if dp.get("developerModeStatus") == "enabled": score += 1
    if score > score_best:
        best, score_best = (hw.get("udid") or d.get("identifier")), score
if best: print(best)
PY
)"
    fi
    rm -f "$DEVJSON"
    if [ -z "$DEVICE_UDID" ]; then
      echo "HATA: Bağlı ve eşleştirilmiş iPhone bulunamadı."
      echo "      iPhone'u kabloyla bağlayın, kilidini açın, 'Bu bilgisayara güven' deyin;"
      echo "      iPhone'da Ayarlar > Gizlilik ve Güvenlik > Geliştirici Modu'nu açın. Sonra yeniden deneyin."
      echo "      (Elle seçmek için: DEVICE=<UDID> DEVELOPMENT_TEAM=$TEAM ./build-ios.sh device)"
      exit 1
    fi
    echo "==> Cihaz için derleniyor (imzalı, Takım: $TEAM, Cihaz: $DEVICE_UDID)"
    set +e
    xcodebuild -project QeniroPDFiOS.xcodeproj -scheme QeniroPDFiOS -configuration Debug \
      -destination "id=$DEVICE_UDID" -derivedDataPath "$DERIVED" \
      -allowProvisioningUpdates DEVELOPMENT_TEAM="$TEAM" CODE_SIGN_STYLE=Automatic \
      build > "$LOG" 2>&1
    STATUS=$?
    set -e
    if [ $STATUS -ne 0 ]; then show_errors; exit $STATUS; fi
    APP="$DERIVED/Build/Products/Debug-iphoneos/Qeniro PDF.app"
    echo "==> iPhone'a kuruluyor"
    xcrun devicectl device install app --device "$DEVICE_UDID" "$APP"
    xcrun devicectl device process launch --device "$DEVICE_UDID" com.qeniro.pdf.ios || \
      echo "Not: Uygulama kuruldu. İlk açılışta iPhone'da Ayarlar > Genel > VPN ve Cihaz Yönetimi'nden geliştiriciye güvenmeniz gerekebilir."
    echo "==> Tamam: Qeniro PDF iPhone'a kuruldu."
    ;;
  *)
    echo "==> iOS Simülatörü için derleniyor (Debug, imzasız)"
    set +e
    xcodebuild -project QeniroPDFiOS.xcodeproj -scheme QeniroPDFiOS -configuration Debug \
      -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' \
      -derivedDataPath "$DERIVED" CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO \
      build > "$LOG" 2>&1
    STATUS=$?
    set -e
    if [ $STATUS -ne 0 ]; then show_errors; exit $STATUS; fi
    APP="$DERIVED/Build/Products/Debug-iphonesimulator/Qeniro PDF.app"
    echo "==> Derleme başarılı: $APP"
    if [ "$MODE" = "run" ]; then
      SIM="$(xcrun simctl list devices available | grep -m1 -E "^[[:space:]]+iPhone" | sed -E 's/.*\(([0-9A-F-]{36})\).*/\1/' || true)"
      if [ -z "$SIM" ]; then
        echo "UYARI: Kullanılabilir iPhone simülatörü bulunamadı (Xcode > Window > Devices and Simulators)."
        exit 0
      fi
      echo "==> Simülatör açılıyor ($SIM)"
      xcrun simctl boot "$SIM" 2>/dev/null || true
      open -a Simulator
      xcrun simctl install "$SIM" "$APP"
      xcrun simctl launch "$SIM" com.qeniro.pdf.ios
    fi
    ;;
esac
