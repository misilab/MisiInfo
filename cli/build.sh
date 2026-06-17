#!/usr/bin/env bash
# Build du binaire CLI misiinfo. Le binaire est ensuite copié dans scripts/.
set -euo pipefail
cd "$(dirname "$0")"
echo "🛠  Compilation misiinfo CLI…"
swiftc -O -parse-as-library -o misiinfo misiinfo.swift \
    -framework Foundation -framework AVFoundation -framework CoreMedia
cp misiinfo ../scripts/
echo "✅ Binaire installé : scripts/misiinfo"
echo "   Tu peux l'installer dans /usr/local/bin avec :"
echo "       sudo cp scripts/misiinfo /usr/local/bin/"
