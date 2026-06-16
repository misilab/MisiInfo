#!/usr/bin/env bash
# Génère docs/appcast.xml depuis les releases publiées sur GitHub.
# Signe chaque DMG avec la clé Ed25519 stockée dans le Keychain (via sign_update).

set -e

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APPCAST="$ROOT/docs/appcast.xml"
REPO="misilab/MisiInfo"
SIGN_UPDATE="$ROOT/scripts/sign_update"
GH="${GH:-/tmp/gh}"
[[ ! -x "$GH" ]] && GH=$(which gh 2>/dev/null || echo "")

if [[ -z "$GH" ]]; then
    echo "❌ gh CLI introuvable"
    exit 1
fi
if [[ ! -x "$SIGN_UPDATE" ]]; then
    echo "❌ scripts/sign_update introuvable. Re-télécharge Sparkle dans /tmp."
    exit 1
fi

echo "📋 Lecture des releases GitHub…"
JSON_FILE=$(mktemp)
$GH api "repos/$REPO/releases?per_page=20" > "$JSON_FILE"

python3 - "$APPCAST" "$REPO" "$SIGN_UPDATE" "$JSON_FILE" <<'PYEOF'
import json, sys, subprocess, os, urllib.request, tempfile, re
from email.utils import format_datetime
from datetime import datetime

appcast_path, repo, sign_update, json_path = sys.argv[1:5]
with open(json_path) as f:
    releases = json.load(f)

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

# Écrit le header + items + footer dans appcast.xml
with open(appcast_path, "w", encoding="utf-8") as f:
    f.write('<?xml version="1.0" encoding="utf-8"?>\n')
    f.write('<rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle"\n')
    f.write('     xmlns:dc="http://purl.org/dc/elements/1.1/" version="2.0">\n')
    f.write('    <channel>\n')
    f.write('        <title>MisiInfo</title>\n')
    f.write('        <description>Notes de mise à jour MisiInfo</description>\n')
    f.write('        <language>fr</language>\n')
    f.write(f'        <link>https://github.com/{repo}</link>\n')

    for r in valid:
        tag = r["tag_name"]
        version = tag.lstrip("vV")
        title = r["name"] or f"MisiInfo {version}"
        date_str = r["published_at"]
        pub_dt = datetime.fromisoformat(date_str.replace("Z", "+00:00"))
        rfc822 = format_datetime(pub_dt)
        notes = (r["body"] or "").strip()
        notes_escaped = notes.replace("]]>", "]]]]><![CDATA[>")

        dmg = next((a for a in r["assets"] if a["name"].lower().endswith(".dmg")), None)
        if not dmg:
            print(f"⚠️  {tag} sans DMG")
            continue

        with tempfile.NamedTemporaryFile(suffix=".dmg", delete=False) as tmp:
            tmp_path = tmp.name
        print(f"⬇️  {tag} : téléchargement {dmg['name']} ({dmg['size']} octets)…")
        urllib.request.urlretrieve(dmg["browser_download_url"], tmp_path)
        print(f"🔏 Signature Ed25519…")
        result = subprocess.run([sign_update, tmp_path], capture_output=True, text=True, check=False)
        os.unlink(tmp_path)

        if result.returncode != 0:
            print(f"⚠️  sign_update a échoué pour {tag} : {result.stderr.strip()}")
            continue
        sig_match = re.search(r'sparkle:edSignature="([^"]+)"\s+length="(\d+)"', result.stdout)
        if not sig_match:
            print(f"⚠️  Pas de signature parsable pour {tag} : {result.stdout}")
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

    f.write('    </channel>\n')
    f.write('</rss>\n')

print("✅ appcast généré :", appcast_path)
PYEOF

rm -f "$JSON_FILE"
echo ""
echo "📄 Appcast : $APPCAST"
echo "👉 git add docs/appcast.xml && git commit -m \"appcast\" && git push"
