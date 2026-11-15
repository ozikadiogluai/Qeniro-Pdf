#!/bin/bash
cd "$(dirname "$0")"
./build.sh run 2>&1 | tee build/son-calistirma.txt
echo
echo "Bitti. Bu pencereyi kapatabilirsiniz."
