#!/bin/bash
# Çift tıklayın: Qeniro PDF'i kabloyla bağlı iPhone'a derleyip kurar.
cd "$(dirname "$0")"
mkdir -p build
TEAM="${DEVELOPMENT_TEAM:-}"
if [ -z "$TEAM" ]; then
  # Önce Xcode'da oturum açılmış hesabın takımı
  TEAM="$(defaults read com.apple.dt.Xcode IDEProvisioningTeamByIdentifier 2>/dev/null \
    | sed -n 's/.*teamID = "\{0,1\}\([A-Z0-9]\{10\}\)"\{0,1\};.*/\1/p' | head -1)"
fi
if [ -z "$TEAM" ]; then
  # Yoksa Anahtar Zinciri'ndeki "Apple Development" sertifikasından
  TEAM="$(security find-certificate -a -c "Apple Development" -p 2>/dev/null \
    | openssl x509 -noout -subject 2>/dev/null \
    | sed -n 's/.*OU *= *\([A-Z0-9]\{10\}\).*/\1/p' | head -1)"
fi
echo "Takım kimliği: ${TEAM:-BULUNAMADI}"
set -o pipefail
DEVELOPMENT_TEAM="$TEAM" ./iOS/build-ios.sh device 2>&1 | tee build/iphone-kur.txt
STATUS=$?
echo
if [ $STATUS -eq 0 ]; then echo "Bitti: Qeniro PDF iPhone'a kuruldu."; else echo "Hata (kod $STATUS). Ayrıntı: build/iphone-kur.txt"; fi
echo "Bu pencereyi kapatabilirsiniz."
