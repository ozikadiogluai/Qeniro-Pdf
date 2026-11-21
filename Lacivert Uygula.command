#!/bin/bash
# Mac uygulamasını derler, Uygulamalar'daki Qeniro PDF'i yeniler, ardından bağlı iPhone'a kurar.
cd "$(dirname "$0")"
mkdir -p build
LOG=build/lacivert-uygula.txt
: > "$LOG"
LSREG=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
echo "==> 0/3 Eski kopyalar temizleniyor" | tee -a "$LOG"
{ echo "-- bulunan kopyalar"; mdfind "kMDItemCFBundleIdentifier == 'com.qeniro.pdf'"; "$LSREG" -dump 2>/dev/null | grep -E "^path:.*Qeniro PDF\.app" | sort -u; } >> "$LOG" 2>&1
for k in "build/Qeniro PDF.app" "build/DerivedData" "$HOME/Library/Developer/QeniroPDF/DerivedData/Build/Products/Debug/Qeniro PDF.app" "$HOME/Library/Developer/QeniroPDF/DerivedData/Build/Products/Release/Qeniro PDF.app"; do
  [ -e "$k" ] && { find "$k" -name "*.app" -maxdepth 6 -type d -exec "$LSREG" -u {} \; 2>/dev/null; rm -rf "$k"; echo "kaldırıldı: $k" >> "$LOG"; }
done
set -o pipefail
echo "==> 1/3 Mac uygulaması derleniyor (Release)" | tee -a "$LOG"
if ./build.sh release 2>&1 | tee -a "$LOG"; then
  APP="build/Qeniro PDF.app"
  echo "==> 2/3 Uygulamalar klasörüne kuruluyor" | tee -a "$LOG"
  osascript -e 'quit app "Qeniro PDF"' 2>/dev/null; sleep 1
  ditto --noextattr --norsrc "$APP" "/Applications/Qeniro PDF.app" && echo "MAC_KURULDU" | tee -a "$LOG"
  /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -u "$APP" 2>/dev/null
  rm -rf "$APP"
  "$LSREG" -u "$HOME/Library/Developer/QeniroPDF/DerivedData/Build/Products/Release/Qeniro PDF.app" 2>/dev/null
  "$LSREG" -f "/Applications/Qeniro PDF.app"; killall Dock 2>/dev/null
  open "/Applications/Qeniro PDF.app"
else
  echo "MAC_HATA" | tee -a "$LOG"
fi
echo "==> 3/3 iPhone'a kuruluyor" | tee -a "$LOG"
if "./iPhone'a Kur.command" 2>&1 | tee -a "$LOG"; then :; fi
echo "BITTI" | tee -a "$LOG"
