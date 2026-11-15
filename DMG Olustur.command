#!/bin/bash
cd "$(dirname "$0")"
./make_dmg.sh 2>&1 | tee build/dmg-olustur.txt
echo
echo "Bitti. Bu pencereyi kapatabilirsiniz."
