import SwiftUI

/// Table des explications pédagogiques affichées en tooltip au survol.
/// La clé correspond au libellé exact d'une `InfoRow` ou d'un terme technique.
/// Les explications sont stockées comme clés de traduction (résolues au render).
nonisolated enum Tooltips {
    static func explanation(for label: String) -> LocalizedStringKey? {
        switch label {
        // Général
        case "Conteneur":
            return "tooltip.Conteneur"
        case "Débit global":
            return "tooltip.Débit global"
        case "UTI":
            return "tooltip.UTI"
        case "Marque majeure (ftyp)", "Marques compatibles":
            return "tooltip.ftyp"

        // Vidéo
        case "Codec":
            return "tooltip.Codec"
        case "Profil / Level":
            return "tooltip.Profil / Level"
        case "Résolution encodée":
            return "tooltip.Résolution encodée"
        case "Résolution d'affichage":
            return "tooltip.Résolution d'affichage"
        case "Pixel aspect ratio":
            return "tooltip.Pixel aspect ratio"
        case "Fréquence d'images":
            return "tooltip.Fréquence d'images"
        case "Mode du débit images":
            return "tooltip.Mode du débit images"
        case "Ordre des trames":
            return "tooltip.Ordre des trames"
        case "Espace de couleurs":
            return "tooltip.Espace de couleurs"
        case "Sous-échantillonnage":
            return "tooltip.Sous-échantillonnage"
        case "Profondeur par composante":
            return "tooltip.Profondeur par composante"
        case "Mode de compression":
            return "tooltip.Mode de compression"
        case "Bits / (Pixel × Image)":
            return "tooltip.Bits / (Pixel × Image)"

        // Colorimétrie
        case "Primaries (gamut)":
            return "tooltip.Primaries"
        case "Fonction de transfert":
            return "tooltip.Fonction de transfert"
        case "Matrice YCbCr":
            return "tooltip.Matrice YCbCr"
        case "Plage de couleurs":
            return "tooltip.Plage de couleurs"
        case "HDR":
            return "tooltip.HDR"
        case "MaxCLL":
            return "tooltip.MaxCLL"
        case "MaxFALL":
            return "tooltip.MaxFALL"
        case "Mastering Display Color Volume":
            return "tooltip.MDCV"

        // Audio
        case "Disposition des canaux":
            return "tooltip.Disposition des canaux"
        case "Fréquence d'échantillonnage":
            return "tooltip.Fréquence d'échantillonnage"
        case "Quantification":
            return "tooltip.Quantification"
        case "Profil audio":
            return "tooltip.Profil audio"
        case "Endianness":
            return "tooltip.Endianness"
        case "Échantillons par frame":
            return "tooltip.Échantillons par frame"

        // Timecode
        case "Timecode de départ", "Timecode de fin":
            return "tooltip.Timecode"
        case "Drop frame":
            return "tooltip.Drop frame"

        default: return nil
        }
    }
}
