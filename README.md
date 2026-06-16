# MisiInfo

Analyse technique de fichiers audio et vidéo — moderne, clair, pédagogique.

MisiInfo est une application macOS native conçue pour les monteurs, chefs opérateurs, étalonneurs, ingénieurs du son, techniciens audiovisuels, enseignants, étudiants, DIT et assistants monteurs. Glissez un fichier audio ou vidéo : MisiInfo affiche en quelques secondes toutes ses caractéristiques techniques avec une interface lisible, sans bruit, et avec un niveau de détail ajustable.

## Fonctionnalités

### Vidéo
- Codec (H.264 / H.265 / ProRes / VP9 / AV1 / Dolby Vision…) avec **profil et level précis** (`High @L4.2`, `Main 10 @L5.1`, …)
- Résolution encodée et d'affichage, pixel aspect ratio (détection anamorphique)
- Fréquence d'images (CFR / VFR auto-détecté)
- Débit estimé + débit par pixel × frame
- Ordre des trames (progressif, TFF, BFF, spatial)
- Profondeur par composante (8 / 10 / 12 / 16 bits)
- Sous-échantillonnage chrominance (4:2:0, 4:2:2, 4:4:4)
- Espace de couleurs (YUV / RGB / RGBA)
- Mode de compression (avec perte / sans perte / non compressé)

### Colorimétrie
- Primaries (BT.709, BT.2020, P3-D65, DCI-P3…)
- Fonction de transfert (BT.709, PQ, HLG, sRGB, gamma 2.2…)
- Matrice YCbCr
- Plage de couleurs (Full / Limited)
- Détection HDR automatique (HDR10, HLG, Dolby Vision)
- Métadonnées HDR (MaxCLL, MaxFALL, Mastering Display)

### Audio
- Codec et **profil exact** (AAC LC, HE-AAC, HE-AAC v2, AC-3, E-AC-3, ALAC, FLAC, Opus…)
- Codec ID détaillé (`mp4a-40-2`, etc.)
- Canaux + disposition positionnelle (`L R C LFE Ls Rs`)
- Fréquence d'échantillonnage + quantification
- Endianness pour PCM
- Échantillons par frame + nombre total d'échantillons

### Timecode
- **Timecode de départ et de fin SMPTE** lus depuis la piste TMCD ou les métadonnées QuickTime
- Drop frame auto-détecté avec syntaxe SMPTE correcte (`HH:MM:SS;FF`)
- Calcul synthétique pour les fichiers sans piste timecode

### Général
- Conteneur, taille, durée, débit global, dates de création/modification
- Encodeur et application d'écriture (depuis les métadonnées)
- UTI Apple, brand MP4 majeur et brands compatibles
- Détection automatique du canal alpha et du HDR au niveau de l'asset

### MediaInfo avancé
Si la bibliothèque [MediaInfoLib](https://mediaarea.net/MediaInfo) est embarquée, MisiInfo expose en mode Expert tous les champs supplémentaires : `Encoded Library` (x264 / x265 exacts), `Writing Application`, `Mode du débit (CBR/VBR)`, `Reference Frames`, `Format Settings GOP`, `Stream Size`, etc.

### Bonus
- Interface **traduite en français, anglais, espagnol** avec sélecteur in-app
- **Export** du rapport en texte
- **Copier** le rapport dans le presse-papier
- **Révéler dans le Finder**
- Mises à jour vérifiées automatiquement via GitHub Releases
- Mode **Simple / Expert** pour ajuster le niveau de détail

## Captures d'écran

_À ajouter._

## Installation

1. Télécharger `MisiInfo.dmg` depuis la [dernière release](https://github.com/misilab/MisiInfo/releases/latest)
2. Double-cliquer le DMG
3. Glisser **MisiInfo** dans **Applications**
4. Lancer depuis le Launchpad

Prérequis : **macOS 14 Sonoma** ou supérieur.

## Compilation depuis les sources

```bash
git clone https://github.com/misilab/MisiInfo.git
cd MisiInfo
./scripts/install_mediainfo.sh    # télécharge libmediainfo.0.dylib
open MediaScope.xcodeproj
```

Pour produire un DMG distribuable :
```bash
./scripts/make_dmg.sh             # build + DMG
./scripts/make_dmg.sh --notarize  # build + DMG + notarisation Apple
```

## Architecture

- **SwiftUI** + **AVFoundation** + **CoreMedia** + **CoreAudio**
- **MediaInfoLib** (BSD-2-Clause) embarquée via `dlopen` pour les champs avancés
- Sandbox App Store ready
- Localisé via Xcode String Catalog

## Licence

[MIT](LICENSE) — voir le fichier LICENSE.

Embarque [MediaInfoLib](https://mediaarea.net/MediaInfo) sous licence BSD-2-Clause, Copyright © MediaArea.net.

## Auteur

Créé par **Matthieu Misiraca** — [misiraca.com](https://www.misiraca.com)
