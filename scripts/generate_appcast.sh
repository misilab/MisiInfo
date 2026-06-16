#!/usr/bin/env bash
# Génère docs/appcast.xml depuis les releases publiées sur GitHub.
# Signe chaque DMG avec la clé privée Sparkle (sign_update).
#
# Usage : ./scripts/generate_appcast.sh
# Pré-requis :
#   - gh CLI authentifié
#   - sign_update installé (fourni par Sparkle : `Sparkle/bin/sign_update`)
#   - clé privée stockée dans le Keychain via : `Sparkle/bin/generate_keys`
#
# Sortie : docs/appcast.xml — à pusher pour que les utilisateurs voient les MAJ.

set -e

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APPCAST="$ROOT/docs/appcast.xml"
REPO="misilab/MisiInfo"
SIGN_UPDATE="${SIGN_UPDATE:-$ROOT/scripts/sign_update}"

if [[ ! -x "$SIGN_UPDATE" ]]; then
    SIGN_UPDATE=$(which sign_update 2>/dev/null || true)
fi
if [[ -z "$SIGN_UPDATE" ]] || [[ ! -x "$SIGN_UPDATE" ]]; then
    echo "❌ sign_update introuvable. Récupère le binaire depuis Sparkle :"
    echo "   curl -L https://github.com/sparkle-project/Sparkle/releases/latest/download/Sparkle-{VERSION}.tar.xz -o /tmp/sparkle.tar.xz"
    echo "   tar xf /tmp/sparkle.tar.xz -C /tmp/"
    echo "   cp /tmp/Sparkle/bin/sign_update $ROOT/scripts/sign_update"
    exit 1
fi

GH="${GH:-/tmp/gh}"
[[ ! -x "$GH" ]] && GH=$(which gh)

echo "📋 Lecture des releases GitHub…"
RELEASES_JSON=$($GH api "repos/$REPO/releases?per_page=20")

cat > "$APPCAST" <<EOF
<?xml version="1.0" encoding="utf-8"?>
<rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle"
     xmlns:dc="http://purl.org/dc/elements/1.1/"
     version="2.0">
    <channel>
        <title>MisiInfo</title>
        <description>Notes de mise à jour MisiInfo</description>
        <language>fr</language>
        <link>https://github.com/$REPO</link>
EOF

echo "$RELEASES_JSON" | python3 - "$APPCAST" "$REPO" "$SIGN_UPDATE" <<'PYEOF'
import json, sys, subprocess, os, urllib.request, tempfile, re
from email.utils import format_datetime
from datetime import datetime

appcast_path = sys.argv[1]
repo = sys.argv[2]
sign_update = sys.argv[3]
releases = json.load(sys.stdin)

# Filtre : pas de prerelease/draft, tag semver vN.N.N
def semver_key(tag):
    m = re.match(r"^v?(\d+)\.(\d+)(?:\.(\d+))?(?:\.(\d+))?$", tag)
    if not m: return None
    return tuple(int(g or 0) for g in m.groups())

valid = []
for r in releases:
    if r.get("draft") or r.get("prerelease"): continue
    if not semver_key(r["tag_name"]): continue
    valid.append(r)
valid.sort(key=lambda r: semver_key(r["tag_name"]), reverse=True)

if not valid:
    print("⚠️  Aucune release semver valide trouvée")
    sys.exit(0)

items = []
with open(appcast_path, "a") as f:
    for r in valid:
        tag = r["tag_name"]
        version = tag.lstrip("vV")
        title = r["name"] or f"MisiInfo {version}"
        date_str = r["published_at"]  # ISO 8601
        pub_dt = datetime.fromisoformat(date_str.replace("Z", "+00:00"))
        rfc822 = format_datetime(pub_dt)
        notes = (r["body"] or "").strip()
        notes_escaped = notes.replace("]]>", "]]]]><![CDATA[>")

        # Asset DMG
        dmg = next((a for a in r["assets"] if a["name"].lower().endswith(".dmg")), None)
        if not dmg:
            print(f"⚠️  {tag} sans DMG")
            continue

        # Téléchargement + signature Ed25519
        with tempfile.NamedTemporaryFile(suffix=".dmg", delete=False) as tmp:
            print(f"⬇️  Téléchargement {dmg['name']} ({dmg['size']} octets)…")
            urllib.request.urlretrieve(dmg["browser_download_url"], tmp.name)
            print(f"🔏 Signature Ed25519…")
            result = subprocess.run(
                [sign_update, tmp.name],
                capture_output=True, text=True, check=False
            )
            os.unlink(tmp.name)
        if result.returncode != 0:
            print(f"⚠️  sign_update a échoué pour {tag} : {result.stderr.strip()}")
            continue
        # sign_update output : sparkle:edSignature="..." length="..."
        sig_match = re.search(r'sparkle:edSignature="([^"]+)"\s+length="(\d+)"', result.stdout)
        if not sig_match:
            print(f"⚠️  Pas de signature parsable pour {tag}")
            continue
        signature = sig_match.group(1)
        length = sig_match.group(2)

        f.write(f"""        <item>
            <title>{title}</title>
            <link>https://github.com/{repo}/releases/tag/{tag}</link>
            <sparkle:version>{version}</sparkle:version>
            <sparkle:shortVersionString>{version}</sparkle:shortVersionString>
            <sparkle:minimumSystemVersion>14.0</sparkle:minimumSystemVersion>
            <pubDate>{rfc822}</pubDate>
            <description><![CDATA[
{notes_escaped}
            ]]></description>
            <enclosure
                url="{dmg['browser_download_url']}"
                sparkle:edSignature="{signature}"
                length="{length}"
                type="application/octet-stream" />
        </item>
""")
        print(f"  ✅ {tag}")

print("✅ appcast généré")
PYEOF

cat >> "$APPCAST" <<EOF
    </channel>
</rss>
EOF

echo ""
echo "📄 Appcast : $APPCAST"
echo "👉 N'oublie pas : git add docs/appcast.xml && git push"
echo "   Les utilisateurs liront l'appcast à :"
echo "   https://raw.githubusercontent.com/$REPO/main/docs/appcast.xml"
