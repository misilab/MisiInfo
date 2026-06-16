#!/usr/bin/env bash
# Téléchargement et préparation des bibliothèques MediaInfoLib (BSD-2-Clause)
# pour intégration manuelle dans Xcode.
#
# Usage : ./scripts/install_mediainfo.sh
# Résultat : Vendor/MediaInfo/{libmediainfo.0.dylib, libzen.0.dylib}
# À ensuite glisser dans Xcode (cf. INSTALL_MEDIAINFO.md).

set -e

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VENDOR_DIR="$ROOT/Vendor/MediaInfo"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

# Version : ajuste si une release plus récente est dispo sur https://mediaarea.net/en/MediaInfo/Download/Mac_OS
MI_VERSION="26.05"
MI_URL="https://mediaarea.net/download/binary/libmediainfo0/${MI_VERSION}/MediaInfo_DLL_${MI_VERSION}_Mac_x86_64+arm64.tar.bz2"

mkdir -p "$VENDOR_DIR"

echo "📦 Téléchargement de MediaInfoLib ${MI_VERSION}…"
curl -L -o "$TMP_DIR/mi.tar.bz2" "$MI_URL"

echo "📂 Extraction…"
tar -xjf "$TMP_DIR/mi.tar.bz2" -C "$TMP_DIR"

# Cherche le .dylib (libzen est statiquement liée dedans depuis 24.x)
DYLIB_MI=$(find "$TMP_DIR" -name "libmediainfo.0.dylib" | head -n 1)

if [[ -z "$DYLIB_MI" ]]; then
    echo "❌ Impossible de trouver libmediainfo.0.dylib dans l'archive."
    exit 1
fi

cp "$DYLIB_MI" "$VENDOR_DIR/"

# Fix install_name : par défaut MediaArea le compile pour /usr/local/lib/
# On le pointe vers @rpath pour qu'il soit trouvable dans le bundle .app/Contents/Frameworks/
echo "🔧 Réécriture du install_name vers @rpath…"
install_name_tool -id @rpath/libmediainfo.0.dylib "$VENDOR_DIR/libmediainfo.0.dylib" 2>/dev/null || true
codesign --remove-signature "$VENDOR_DIR/libmediainfo.0.dylib" 2>/dev/null || true

# Headers C pour référence
HEADER_DIR=$(find "$TMP_DIR" -type d -name "Include" | head -n 1)
if [[ -n "$HEADER_DIR" ]]; then
    cp -R "$HEADER_DIR" "$VENDOR_DIR/"
fi

echo ""
echo "✅ Bibliothèque installée :"
echo "   $VENDOR_DIR/libmediainfo.0.dylib"
echo ""
echo "Architectures :"
lipo -info "$VENDOR_DIR/libmediainfo.0.dylib" || true
echo ""
echo "👉 Étape suivante : voir INSTALL_MEDIAINFO.md pour les ajouter au projet Xcode."
