# Activer les mises à jour automatiques Sparkle

Sparkle est le framework standard macOS pour les mises à jour automatiques. Une fois activé, les utilisateurs auront un **vrai bouton "Installer"** : l'app se quitte, télécharge la nouvelle version, remplace l'ancienne dans /Applications et redémarre — **tout seule en 5 secondes**.

C'est ce qu'utilisent 1Password, Tower, Things, Notion, Bartender…

## Pourquoi maintenant

Avant Sparkle, le flux utilisateur était : *« Télécharger DMG → ouvrir → glisser dans Applications → relancer »*. Pénible.

Avec Sparkle : *« Cliquer Installer »*. Point.

---

## Étape 1 — Ajouter le Swift Package (2 min)

1. Dans Xcode : **File → Add Package Dependencies…**
2. Tape dans la barre de recherche en haut à droite :
   ```
   https://github.com/sparkle-project/Sparkle
   ```
3. Dependency Rule : **Up to Next Major Version** → from `2.0.0`
4. **Add Package** → Add the `Sparkle` library → Add Package

Le code Swift dans `Update/SparkleManager.swift` utilise déjà `#if canImport(Sparkle)` — dès que le package est ajouté, il bascule automatiquement vers la vraie implémentation.

## Étape 2 — Générer la paire de clés Ed25519 (1 min, **UNE SEULE FOIS**)

Sparkle signe chaque DMG avec une clé Ed25519 que **toi seul possèdes**. Personne ne peut diffuser une fausse mise à jour.

Récupère les outils Sparkle :
```bash
cd /tmp
curl -L -o sparkle.tar.xz https://github.com/sparkle-project/Sparkle/releases/latest/download/Sparkle-2.6.4.tar.xz
mkdir sparkle && tar xf sparkle.tar.xz -C sparkle
cp sparkle/bin/sign_update ~/Desktop/MediaScope/scripts/sign_update
chmod +x ~/Desktop/MediaScope/scripts/sign_update

# Génère et stocke la paire dans le Keychain
sparkle/bin/generate_keys
```

`generate_keys` te montrera **la clé publique** (commence par `q3F…`). **Copie-la**.

⚠️ La clé privée reste dans ton Keychain. NE LA PARTAGE JAMAIS. Si tu la perds, plus aucune mise à jour ne fonctionnera pour les utilisateurs existants.

## Étape 3 — Build Settings (1 min)

Dans Xcode → cible MediaScope → **Build Settings** → cherche `INFOPLIST_KEY`, et ajoute via **+ → Add User-Defined Setting** ces deux entrées :

| Setting name | Value |
|---|---|
| `INFOPLIST_KEY_SUFeedURL` | `https://raw.githubusercontent.com/misilab/MisiInfo/main/docs/appcast.xml` |
| `INFOPLIST_KEY_SUPublicEDKey` | `(colle ta clé publique générée à l'étape 2)` |

## Étape 4 — Première release Sparkle

```bash
./scripts/make_dmg.sh --notarize --version 1.3.0
./scripts/generate_appcast.sh
git add docs/appcast.xml
git commit -m "Update appcast for v1.3.0"
git push
~/bin/gh release create v1.3.0 ~/Desktop/MisiInfo.dmg docs/MisiInfo-Manual.pdf \
    --repo misilab/MisiInfo --title "MisiInfo 1.3.0" --notes "..."
```

Le script `generate_appcast.sh` :
1. Lit toutes les releases publiées sur GitHub
2. Télécharge chaque DMG
3. Signe avec ta clé Ed25519
4. Génère `docs/appcast.xml`

Les utilisateurs lisent ce XML via `raw.githubusercontent.com` et voient les MAJ disponibles.

## Étape 5 — Vérifier

- Lance MisiInfo
- Menu **MisiInfo → Vérifier les mises à jour…** (ou clic sur le bouton ↻ de la toolbar)
- Alerte native Sparkle qui propose **Installer**
- Click → téléchargement → quit → install → relaunch automatiques

---

## Workflow pour les prochaines releases

```bash
# 1. Build + DMG + notarisation
./scripts/make_dmg.sh --notarize --version 1.X.Y

# 2. Crée la release GitHub avec le DMG
~/bin/gh release create v1.X.Y ~/Desktop/MisiInfo.dmg docs/MisiInfo-Manual.pdf \
    --repo misilab/MisiInfo --title "MisiInfo 1.X.Y" --notes "..."

# 3. Régénère l'appcast (signe les DMG, publie le XML)
./scripts/generate_appcast.sh
git add docs/appcast.xml && git commit -m "Appcast for v1.X.Y" && git push
```

**That's it.** Tes utilisateurs auront la MAJ en 1 clic dans les minutes qui suivent.

## En cas de problème

- **« Sparkle non installé »** dans une alerte → tu n'as pas encore fait l'étape 1
- **Signature invalide** → ta clé publique dans Info.plist ne correspond pas à la privée du Keychain → recommencer étape 2 + 3
- **« Impossible de vérifier »** → l'appcast n'est pas accessible (vérifier que `docs/appcast.xml` est bien push sur main)

Logs Sparkle : `Console.app` → filtrer par `Sparkle` ou `org.sparkle-project.Sparkle`.
