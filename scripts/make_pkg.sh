#!/usr/bin/env bash
# Construit un installateur .pkg signé Developer ID Installer + notarisé Apple.
# Inclut MisiInfo.app dans /Applications et le binaire CLI dans /usr/local/bin.
# La fenêtre d'installation affiche l'EULA (LICENSE.txt) qui doit être acceptée.
#
# Usage : ./scripts/make_pkg.sh --version 1.4.0 [--notarize]
set -euo pipefail

VERSION="1.4.0"
NOTARIZE=false
KEYCHAIN_PROFILE="MisiInfoNotarize"
TEAM_ID="SM6L2XLUBA"
BUNDLE_ID="fr.misilab.MisiInfo"
PROJ_DIR="$(cd "$(dirname "$0")/.." && pwd)"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --version) VERSION="$2"; shift 2 ;;
        --notarize) NOTARIZE=true; shift ;;
        --keychain-profile) KEYCHAIN_PROFILE="$2"; shift 2 ;;
        *) echo "Option inconnue : $1"; exit 1 ;;
    esac
done

cd "$PROJ_DIR"

echo "📦 Construction PKG MisiInfo $VERSION"

# 1. Vérifier qu'on a un Developer ID Installer
INSTALLER_CERT=$(security find-identity -p basic -v 2>&1 | grep "Developer ID Installer" | head -1 | awk -F'"' '{print $2}')
if [[ -z "$INSTALLER_CERT" ]]; then
    echo "❌ Aucun certificat Developer ID Installer trouvé."
    echo "   Tu dois en créer un depuis Apple Developer → Certificates."
    echo "   (différent de Developer ID Application qui sert pour le DMG)"
    exit 1
fi
echo "🔏 Certificat : $INSTALLER_CERT"

# 2. Reconstruire l'app Release notarisée si pas encore présente
APP_SRC=""
if [[ -d "$HOME/Library/Developer/Xcode/DerivedData" ]]; then
    APP_SRC=$(find "$HOME/Library/Developer/Xcode/DerivedData" -name "MisiInfo.app" -path "*Release*" -not -path "*Index*" 2>/dev/null | head -1)
fi
if [[ -z "$APP_SRC" || ! -d "$APP_SRC" ]]; then
    echo "🛠  Aucune build Release trouvée. Lancement du build…"
    ARCHIVE_PATH="$HOME/Library/Developer/Xcode/DerivedData/MisiInfo.xcarchive"
    rm -rf "$ARCHIVE_PATH"
    xcodebuild archive \
        -project MediaScope.xcodeproj \
        -scheme MediaScope \
        -configuration Release \
        -archivePath "$ARCHIVE_PATH" \
        MARKETING_VERSION="$VERSION" \
        CURRENT_PROJECT_VERSION="$VERSION" 2>&1 | tail -5
    EXPORT_DIR=$(mktemp -d)
    xcodebuild -exportArchive \
        -archivePath "$ARCHIVE_PATH" \
        -exportPath "$EXPORT_DIR" \
        -exportOptionsPlist scripts/ExportOptions.plist 2>&1 | tail -3
    APP_SRC=$(find "$EXPORT_DIR" -name "*.app" -type d -maxdepth 2 | head -1)
fi
echo "📁 App source : $APP_SRC"

# 3. Préparer le staging pour pkgbuild
STAGE_APP=$(mktemp -d)
mkdir -p "$STAGE_APP/Applications"
cp -R "$APP_SRC" "$STAGE_APP/Applications/MisiInfo.app"

STAGE_CLI=$(mktemp -d)
mkdir -p "$STAGE_CLI/usr/local/bin"
cp "$PROJ_DIR/scripts/misiinfo" "$STAGE_CLI/usr/local/bin/misiinfo"
chmod +x "$STAGE_CLI/usr/local/bin/misiinfo"

# Signer le binaire CLI avec Developer ID Application + hardened runtime + timestamp
# (exigé par la notarisation Apple — Installer cert ne suffit pas pour les exécutables)
APP_CERT=$(security find-identity -p codesigning -v 2>&1 | grep "Developer ID Application" | head -1 | awk -F'"' '{print $2}')
if [[ -z "$APP_CERT" ]]; then
    echo "❌ Aucun certificat Developer ID Application trouvé (nécessaire pour signer le CLI)."
    exit 1
fi
echo "🔏 Signature du CLI avec $APP_CERT…"
codesign --force --options runtime --timestamp --sign "$APP_CERT" "$STAGE_CLI/usr/local/bin/misiinfo"
codesign --verify --verbose "$STAGE_CLI/usr/local/bin/misiinfo" 2>&1 | tail -3

# 4. pkgbuild des composants
PKG_BUILD=$(mktemp -d)
COMPONENT_PLIST="$PKG_BUILD/component.plist"
cat > "$COMPONENT_PLIST" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><array><dict>
    <key>BundleHasStrictIdentifier</key><true/>
    <key>BundleIsRelocatable</key><false/>
    <key>BundleIsVersionChecked</key><true/>
    <key>BundleOverwriteAction</key><string>upgrade</string>
    <key>RootRelativeBundlePath</key><string>Applications/MisiInfo.app</string>
</dict></array></plist>
EOF
pkgbuild \
    --root "$STAGE_APP" \
    --identifier "$BUNDLE_ID" \
    --version "$VERSION" \
    --install-location "/" \
    --component-plist "$COMPONENT_PLIST" \
    "$PKG_BUILD/MisiInfo.pkg" 2>&1 | tail -3

pkgbuild \
    --root "$STAGE_CLI" \
    --identifier "${BUNDLE_ID}.cli" \
    --version "$VERSION" \
    --install-location "/" \
    "$PKG_BUILD/MisiInfoCLI.pkg" 2>&1 | tail -3

# 5. productbuild avec licence + welcome + conclusion
FINAL_PKG="$HOME/Desktop/MisiInfo-$VERSION-Installer.pkg"
SIGNED_PKG="$HOME/Desktop/MisiInfo-$VERSION.pkg"

productbuild \
    --distribution "$PROJ_DIR/pkg/distribution.xml" \
    --resources "$PROJ_DIR/pkg" \
    --package-path "$PKG_BUILD" \
    --version "$VERSION" \
    "$FINAL_PKG" 2>&1 | tail -3

# 6. Signature
echo "🔏 Signature avec $INSTALLER_CERT…"
productsign --sign "$INSTALLER_CERT" "$FINAL_PKG" "$SIGNED_PKG"
rm -f "$FINAL_PKG"
echo "✅ PKG signé : $SIGNED_PKG  ($(du -h "$SIGNED_PKG" | awk '{print $1}'))"

# 7. Notarisation
if [[ "$NOTARIZE" == "true" ]]; then
    echo ""
    echo "📤 Soumission Apple Notary…"
    xcrun notarytool submit "$SIGNED_PKG" \
        --keychain-profile "$KEYCHAIN_PROFILE" \
        --wait 2>&1 | tee /tmp/notarize.log
    if grep -q "status: Accepted" /tmp/notarize.log; then
        echo "📎 Staple…"
        xcrun stapler staple "$SIGNED_PKG" 2>&1 | tail -2
        echo "✅ PKG notarisé et stapled"
    else
        echo "❌ Notarisation refusée. Voir le log ci-dessus."
        exit 1
    fi
fi

echo ""
echo "🚀 PKG prêt : $SIGNED_PKG"
echo ""
echo "Test d'installation :"
echo "  open \"$SIGNED_PKG\""
echo ""
echo "Étapes suivantes :"
echo "  gh release upload v$VERSION \"$SIGNED_PKG\" --repo misilab/MisiInfo --clobber"
