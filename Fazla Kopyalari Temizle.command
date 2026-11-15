#!/bin/bash
# Launchpad'de görünen fazladan Qeniro PDF kopyalarını kaldırır.
# Yalnızca /Applications/Qeniro PDF.app kalır. Silinenler derleme ara kopyalarıdır,
# gerektiğinde build.sh ile yeniden oluşur.
cd "$(dirname "$0")"
LSREG=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
KOPYALAR=(
  "build/Qeniro PDF.app"
  "build/DerivedData"
  "$HOME/Library/Developer/QeniroPDF/DerivedData/Build/Products/Debug/Qeniro PDF.app"
  "$HOME/Library/Developer/QeniroPDF/DerivedData/Build/Products/Release/Qeniro PDF.app"
)
for k in "${KOPYALAR[@]}"; do
  if [ -e "$k" ]; then
    find "$k" -name "*.app" -maxdepth 6 -type d -exec "$LSREG" -u {} \; 2>/dev/null
    rm -rf "$k" && echo "Kaldırıldı: $k"
  fi
done
mkdir -p "$HOME/Library/Developer/QeniroPDF/DerivedData"
touch "$HOME/Library/Developer/QeniroPDF/DerivedData/.metadata_never_index"
if [ -d "/Applications/Qeniro PDF.app" ]; then
  "$LSREG" -f "/Applications/Qeniro PDF.app"
  echo "Kalan: /Applications/Qeniro PDF.app"
fi
killall Dock 2>/dev/null
echo
echo "Bitti. Launchpad'de artık tek Qeniro PDF görünmeli. Bu pencereyi kapatabilirsiniz."
