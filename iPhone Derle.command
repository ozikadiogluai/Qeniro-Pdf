#!/bin/bash
# Çift tıklayın: Qeniro PDF iPhone sürümünü iOS Simülatörü için derler.
# Çıktı build/ios-derle.txt dosyasına da yazılır (hata olursa bu dosyayı Claude'a iletin).
cd "$(dirname "$0")"
mkdir -p build
set -o pipefail
./iOS/build-ios.sh "$@" 2>&1 | tee build/ios-derle.txt
STATUS=$?
echo
if [ $STATUS -eq 0 ]; then
  echo "Bitti. Çıktı: build/ios-derle.txt"
else
  echo "Derleme hata verdi (kod $STATUS). Ayrıntılar: build/ios-derle.txt ve build/ios-build.log"
fi
read -n 1 -s -r -p "Kapatmak için bir tuşa basın…"
echo
