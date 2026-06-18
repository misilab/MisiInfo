#!/usr/bin/env bash
# Build Release + DMG drag-to-install + notarisation Apple.
#
# Utilise le workflow `xcodebuild archive + exportArchive` avec la méthode
# `developer-id` pour produire un binaire correctement signé avec le certificat
# Developer ID Application (compatible Notary Service Apple).
#
# Pré-requis pour la notarisation (à faire UNE SEULE FOIS) :
#   xcrun notarytool store-credentials "MisiInfoNotarize" \
#       --apple-id "ton@apple.id" \
#       --team-id "SM6L2XLUBA" \
#       --password "xxxx-xxxx-xxxx-xxxx"   # mot de passe app-specific
#
# Usage :
#   ./scripts/make_dmg.sh                  # build + DMG signé Developer ID
#   ./scripts/make_dmg.sh --notarize       # build + DMG + notarisation + staple

set -e

NOTARIZE=false
KEYCHAIN_PROFILE="MisiInfoNotarize"
VERSION_OVERRIDE=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --notarize) NOTARIZE=true; shift ;;
        --keychain-profile=*) KEYCHAIN_PROFILE="${1#*=}"; shift ;;
        --version) VERSION_OVERRIDE="$2"; shift 2 ;;
        --version=*) VERSION_OVERRIDE="${1#*=}"; shift ;;
        *) shift ;;
    esac
done

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="MisiInfo"
VOLUME_NAME="MisiInfo"
ARCHIVE_PATH="$(mktemp -d)/MediaScope.xcarchive"
EXPORT_DIR="$(mktemp -d)"
STAGING="$(mktemp -d)"
DMG_OUT="$HOME/Desktop/${APP_NAME}.dmg"
trap 'rm -rf "$(dirname "$ARCHIVE_PATH")" "$EXPORT_DIR" "$STAGING"' EXIT

echo "🛠  Archive Release (signature Developer ID)…"
EXTRA_BUILD_ARGS=()
if [[ -n "$VERSION_OVERRIDE" ]]; then
    echo "📌 Version override : $VERSION_OVERRIDE"
    EXTRA_BUILD_ARGS+=("MARKETING_VERSION=$VERSION_OVERRIDE")
fi
xcodebuild archive \
    -project "$ROOT/MediaScope.xcodeproj" \
    -scheme MediaScope \
    -configuration Release \
    -archivePath "$ARCHIVE_PATH" \
    -destination 'platform=macOS' \
    "${EXTRA_BUILD_ARGS[@]}" \
    2>&1 | grep -E "^(/|error:|warning:|\*\*)" | tail -20 || true

if [[ ! -d "$ARCHIVE_PATH" ]]; then
    echo "❌ Archive échouée"
    exit 1
fi

echo "📤 Export Developer ID…"
xcodebuild -exportArchive \
    -archivePath "$ARCHIVE_PATH" \
    -exportOptionsPlist "$ROOT/scripts/ExportOptions.plist" \
    -exportPath "$EXPORT_DIR" \
    2>&1 | grep -E "^(/|error:|warning:|\*\*|Exported)" | tail -10 || true

APP_SRC=$(find "$EXPORT_DIR" -name "*.app" -type d -maxdepth 2 | head -1)
if [[ -z "$APP_SRC" ]]; then
    echo "❌ Export échoué — vérifie que ton certificat Developer ID est valide :"
    echo "   security find-identity -p codesigning -v | grep 'Developer ID'"
    exit 1
fi
echo "📦 App exportée : $APP_SRC  ($(basename "$APP_SRC"))"

echo "🔐 Vérification de la signature…"
codesign --verify --deep --strict --verbose=2 "$APP_SRC" 2>&1 | head -10
codesign --display --verbose=2 "$APP_SRC" 2>&1 | grep -E "Authority|TeamIdentifier|Timestamp" | head -5

echo "📂 Mise en scène DMG…"
cp -R "$APP_SRC" "$STAGING/${APP_NAME}.app"
ln -s /Applications "$STAGING/Applications"

if [[ -f "$STAGING/${APP_NAME}.app/Contents/Frameworks/libmediainfo.0.dylib" ]]; then
    echo "✅ libmediainfo.0.dylib présente"
fi

echo "💿 Création du DMG…"
rm -f "$DMG_OUT"
hdiutil create \
    -volname "$VOLUME_NAME" \
    -srcfolder "$STAGING" \
    -ov \
    -format UDZO \
    -imagekey zlib-level=9 \
    "$DMG_OUT" >/dev/null

# Signature du DMG aussi (recommandé pour la notarisation)
DEVID=$(security find-identity -p codesigning -v | grep "Developer ID Application" | head -1 | awk -F'"' '{print $2}')
if [[ -n "$DEVID" ]]; then
    codesign --force --sign "$DEVID" --timestamp "$DMG_OUT" 2>&1 || echo "⚠️ Signature DMG échouée"
fi

SIZE=$(du -h "$DMG_OUT" | cut -f1)
echo "✅ DMG : $DMG_OUT  ($SIZE)"

# Notarisation
if [[ "$NOTARIZE" == "true" ]]; then
    echo ""
    echo "📤 Soumission à Apple Notary Service (peut prendre 1–10 min)…"
    if ! xcrun notarytool submit "$DMG_OUT" \
        --keychain-profile "$KEYCHAIN_PROFILE" \
        --wait \
        --output-format plist > /tmp/notarize.plist; then
        echo "❌ Soumission échouée."
        exit 1
    fi

    STATUS=$(/usr/libexec/PlistBuddy -c "Print :status" /tmp/notarize.plist 2>/dev/null || echo "unknown")
    SUBMISSION_ID=$(/usr/libexec/PlistBuddy -c "Print :id" /tmp/notarize.plist 2>/dev/null || echo "unknown")

    if [[ "$STATUS" != "Accepted" ]]; then
        echo "❌ Notarisation refusée (status=$STATUS)"
        echo "   xcrun notarytool log $SUBMISSION_ID --keychain-profile $KEYCHAIN_PROFILE"
        exit 1
    fi
    echo "✅ Notarisation acceptée (id=$SUBMISSION_ID)"

    echo "📎 Staple du ticket…"
    xcrun stapler staple "$DMG_OUT"
    xcrun stapler validate "$DMG_OUT"
    echo "✅ DMG notarisé et stapled"
fi

echo ""
echo "🚀 DMG prêt : $DMG_OUT"

# Génère aussi un .zip du .app pour Sparkle (auto-install 1-clic).
# Sparkle 2.x ne sait pas auto-installer un DMG : sans ZIP, l'utilisateur doit
# monter manuellement et glisser-déposer. Le ZIP est extrait silencieusement.
ZIP_OUT="$HOME/Desktop/MisiInfo-${VERSION_OVERRIDE:-1.0.0}.zip"
echo ""
echo "🗜  Génération ZIP Sparkle…"
ZIP_TMP=$(mktemp -d)
# Re-mount le DMG notarisé pour récupérer l'app post-notarisation (avec staple).
hdiutil attach "$DMG_OUT" -nobrowse -quiet -mountpoint "$ZIP_TMP/mount"
ditto -c -k --sequesterRsrc --keepParent "$ZIP_TMP/mount/MisiInfo.app" "$ZIP_OUT"
hdiutil detach "$ZIP_TMP/mount" -quiet
rm -rf "$ZIP_TMP"
ZIP_SIZE=$(du -h "$ZIP_OUT" | cut -f1)
echo "✅ ZIP prêt : $ZIP_OUT  ($ZIP_SIZE)"

echo ""
echo "Étapes suivantes pour publier :"
echo "  1. /tmp/gh release create v${VERSION_OVERRIDE:-X.Y.Z} \"$DMG_OUT\" \"$ZIP_OUT\" docs/MisiInfo-Manual.pdf \\"
echo "         --repo misilab/MisiInfo --title \"MisiInfo ${VERSION_OVERRIDE:-X.Y.Z}\" --notes \"...\""
echo "  2. ./scripts/generate_appcast.sh   # signe les ZIP/DMG + génère docs/appcast.xml"
echo "  3. git add docs/appcast.xml && git commit -m \"Appcast v${VERSION_OVERRIDE:-X.Y.Z}\" && git push"
