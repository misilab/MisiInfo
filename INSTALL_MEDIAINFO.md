# Activer MediaInfoLib dans MediaScope

MediaScope fonctionne **sans MediaInfoLib** — toutes les données extraites via AVFoundation restent affichées. L'intégration de la bibliothèque ajoute des champs supplémentaires que macOS ne fournit pas en natif :

- Mode du débit précis (**CBR / VBR / VBR with avg**)
- **Format profile** détaillé (H.264 High@L4.0, HEVC Main 10@L5.1, AAC LC, etc.)
- **Encoded Library** (ex : `x264 - core 161 r3027`)
- **Writing application** / **Writing library** (FFmpeg, mkvmerge, Logic Pro X…)
- **Codec ID** (vs FourCC)
- **Reference frames** count
- **Stream size** par piste
- **Compression ratio**
- Scan type / order détaillé
- Et tous les champs natifs de MediaInfo, exposés en mode Expert

Licence : **BSD-2-Clause**, compatible Mac App Store.

---

## Étape 1 — Télécharger les bibliothèques

Depuis la racine du projet :

```bash
chmod +x scripts/install_mediainfo.sh
./scripts/install_mediainfo.sh
```

Résultat : `Vendor/MediaInfo/libmediainfo.0.dylib` (universel arm64 + x86_64, libzen incluse statiquement).

---

## Étape 2 — Ajouter les `.dylib` au projet Xcode

1. Ouvre **MediaScope.xcodeproj** dans Xcode.
2. Sélectionne la cible **MediaScope** (à gauche, l'app bleue).
3. Va dans l'onglet **General** → section **Frameworks, Libraries, and Embedded Content**.
4. Clique sur le **+** → **Add Other… → Add Files…**
5. Sélectionne `Vendor/MediaInfo/libmediainfo.0.dylib`.
6. Dans la colonne **Embed**, choisis **« Embed & Sign »**.

Xcode va automatiquement la copier dans le bundle `.app/Contents/Frameworks/` et la signer.

---

## Étape 3 — Vérifier

Compile et lance l'app (⌘R). Charge un fichier vidéo : une nouvelle section **« MediaInfo avancé »** doit apparaître en bas du rapport, sous les Métadonnées.

Si elle n'apparaît pas :

```bash
# Vérifie que les dylib sont bien dans le bundle
ls -la "$(find ~/Library/Developer/Xcode/DerivedData -name 'MediaScope.app' | head -n 1)/Contents/Frameworks/"
```

Tu dois voir `libmediainfo.0.dylib`.

---

## Étape 4 — Distribution Mac App Store

Les `.dylib` étant déjà **embed & signed** par Xcode, la build TestFlight / App Store fonctionnera sans manipulation supplémentaire. **Aucune entitlement réseau** n'est requise — MediaInfo analyse uniquement le fichier local que l'utilisateur ouvre.

Vérifie la licence dans **About** : ajouter une mention "*Powered by MediaInfo® — Copyright © MediaArea.net, BSD-2-Clause*" est obligatoire d'après la licence BSD.

---

## Mise à jour

Pour passer à une version plus récente de MediaInfoLib :

1. Modifie la variable `MI_VERSION` dans `scripts/install_mediainfo.sh`.
2. Relance le script.
3. Recompile dans Xcode (la dylib est écrasée automatiquement).
