#!/bin/bash
# Qeniro PDF kurulum dosyası (DMG) oluşturur.
# Kullanım: ./make_dmg.sh   ->  "Qeniro PDF.dmg" proje klasörüne yazılır
set -euo pipefail
cd "$(dirname "$0")"

./build.sh release

APP="build/Qeniro PDF.app"
if [ ! -d "$APP" ]; then
  echo "HATA: $APP bulunamadı, Release derlemesi başarısız olmuş olabilir."
  exit 1
fi

VERSION="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$APP/Contents/Info.plist" 2>/dev/null || echo 1.0)"
DMG="Qeniro PDF ${VERSION}.dmg"
STAGE="$(mktemp -d)/Qeniro PDF"
mkdir -p "$STAGE"

echo "==> DMG içeriği hazırlanıyor"
ditto --noextattr --norsrc "$APP" "$STAGE/Qeniro PDF.app"
ln -s /Applications "$STAGE/Uygulamalar"

echo "==> DMG oluşturuluyor: $DMG"
rm -f "$DMG"
hdiutil create -volname "Qeniro PDF" -srcfolder "$STAGE" -ov -format UDZO -fs HFS+ "$DMG" >/dev/null
rm -rf "$(dirname "$STAGE")"
xattr -c "$DMG" 2>/dev/null || true

# Ara kopyaları kaldır ve Launchpad kaydını sil (yalnızca Uygulamalar'daki kalsın).
LSREG=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
"$LSREG" -u "$APP" 2>/dev/null || true
"$LSREG" -u "$HOME/Library/Developer/QeniroPDF/DerivedData/Build/Products/Release/Qeniro PDF.app" 2>/dev/null || true
rm -rf "$APP"

echo
echo "==> Hazır: $(pwd)/$DMG"
echo "    Çift tıkla, açılan pencerede 'Qeniro PDF' simgesini 'Uygulamalar' klasörüne sürükle."
echo "    İlk açılışta Mac uyarı verirse: Uygulamalar'da sağ tık > Aç."
open -R "$DMG"
