import AppKit
import CoreText
import PDFKit

// Usage : swift make_manual.swift output.pdf logo.png

let outputURL = URL(fileURLWithPath: CommandLine.arguments[1])
let logoURL = URL(fileURLWithPath: CommandLine.arguments[2])

// A4
let pageSize = CGSize(width: 595, height: 842)
let marginX: CGFloat = 60
let marginTop: CGFloat = 70
let marginBottom: CGFloat = 70
let contentWidth = pageSize.width - 2 * marginX

// MARK: - Couleurs

let cAccent = NSColor(red: 0.05, green: 0.35, blue: 0.55, alpha: 1.0)    // bleu profond
let cAccent2 = NSColor(red: 0.15, green: 0.50, blue: 0.70, alpha: 1.0)   // bleu mid
let cText = NSColor(white: 0.12, alpha: 1.0)                              // presque noir
let cMuted = NSColor(white: 0.40, alpha: 1.0)
let cMono = NSColor(red: 0.15, green: 0.40, blue: 0.70, alpha: 1.0)
let cMonoBg = NSColor(white: 0.95, alpha: 1.0)

// MARK: - Styles attributs

func attrs(font: NSFont, color: NSColor = cText, paraSpacing: CGFloat = 6, lineSpacing: CGFloat = 3, headIndent: CGFloat = 0) -> [NSAttributedString.Key: Any] {
    let s = NSMutableParagraphStyle()
    s.lineBreakMode = .byWordWrapping
    s.paragraphSpacing = paraSpacing
    s.lineSpacing = lineSpacing
    s.headIndent = headIndent
    s.firstLineHeadIndent = headIndent > 0 ? 12 : 0
    return [
        .font: font,
        .foregroundColor: color,
        .paragraphStyle: s
    ]
}

let h1Attrs = attrs(font: NSFont.systemFont(ofSize: 24, weight: .heavy), color: cAccent, paraSpacing: 12)
let h2Attrs = attrs(font: NSFont.systemFont(ofSize: 16, weight: .bold), color: cAccent2, paraSpacing: 8)
let h3Attrs = attrs(font: NSFont.systemFont(ofSize: 12, weight: .semibold), color: cText, paraSpacing: 4)
let bodyAttrs = attrs(font: NSFont.systemFont(ofSize: 11), color: cText, paraSpacing: 6, lineSpacing: 4)
let bulletAttrs = attrs(font: NSFont.systemFont(ofSize: 11), color: cText, paraSpacing: 4, lineSpacing: 3, headIndent: 18)

// MARK: - Contexte PDF

var mediaBox = CGRect(origin: .zero, size: pageSize)
guard let consumer = CGDataConsumer(url: outputURL as CFURL),
      let ctx = CGContext(consumer: consumer, mediaBox: &mediaBox, [
          kCGPDFContextTitle as String: "MisiInfo — Manuel utilisateur" as CFString,
          kCGPDFContextAuthor as String: "Matthieu Misiraca" as CFString,
          kCGPDFContextCreator as String: "MisiInfo" as CFString
      ] as CFDictionary)
else { fatalError("PDF context") }

let nsCtx = NSGraphicsContext(cgContext: ctx, flipped: false)

var currentY: CGFloat = marginTop  // distance depuis le haut
var pageOpen = false

func beginPage() {
    var box = mediaBox
    ctx.beginPDFPage([kCGPDFContextMediaBox as String: NSData(bytes: &box, length: MemoryLayout<CGRect>.size)] as CFDictionary)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = nsCtx
    pageOpen = true
    currentY = marginTop
}

func endPage() {
    guard pageOpen else { return }
    NSGraphicsContext.restoreGraphicsState()
    ctx.endPDFPage()
    pageOpen = false
}

func newPage() {
    endPage()
    beginPage()
}

/// Rendu d'un bloc de texte attribué avec CoreText (calcul de hauteur fiable).
func drawBlock(_ string: String, attributes: [NSAttributedString.Key: Any], width: CGFloat = contentWidth, indent: CGFloat = 0, spaceBefore: CGFloat = 0) {
    let attrString = NSAttributedString(string: string, attributes: attributes)
    let framesetter = CTFramesetterCreateWithAttributedString(attrString as CFAttributedString)
    let suggested = CTFramesetterSuggestFrameSizeWithConstraints(
        framesetter,
        CFRange(location: 0, length: attrString.length),
        nil,
        CGSize(width: width, height: .greatestFiniteMagnitude),
        nil
    )
    let blockHeight = suggested.height + 2  // marge de sécurité

    // Saut de page si nécessaire
    if currentY + spaceBefore + blockHeight > pageSize.height - marginBottom {
        newPage()
    }
    currentY += spaceBefore

    let drawY = pageSize.height - currentY - blockHeight
    let path = CGPath(rect: CGRect(x: marginX + indent, y: drawY, width: width, height: blockHeight), transform: nil)
    let frame = CTFramesetterCreateFrame(framesetter, CFRange(location: 0, length: attrString.length), path, nil)
    CTFrameDraw(frame, ctx)
    currentY += blockHeight
    let paraStyle = attributes[.paragraphStyle] as? NSMutableParagraphStyle
    currentY += paraStyle?.paragraphSpacing ?? 0
}

func drawSeparator() {
    if currentY + 18 > pageSize.height - marginBottom { newPage() }
    let drawY = pageSize.height - currentY - 8
    ctx.saveGState()
    ctx.setStrokeColor(NSColor(white: 0.85, alpha: 1.0).cgColor)
    ctx.setLineWidth(0.6)
    ctx.move(to: CGPoint(x: marginX, y: drawY))
    ctx.addLine(to: CGPoint(x: pageSize.width - marginX, y: drawY))
    ctx.strokePath()
    ctx.restoreGState()
    currentY += 18
}

func drawFooterPageNumber(_ n: Int) {
    let attr = NSAttributedString(string: "\(n)", attributes: [
        .font: NSFont.systemFont(ofSize: 9),
        .foregroundColor: cMuted
    ])
    let size = attr.size()
    attr.draw(at: CGPoint(x: (pageSize.width - size.width) / 2, y: 30))
}

// MARK: - Couverture (fond BLANC)

beginPage()

// Fond blanc déjà par défaut. On ajoute juste un bandeau cyan en haut pour donner du caractère.
ctx.saveGState()
let bandHeight: CGFloat = 8
ctx.setFillColor(CGColor(srgbRed: 0.15, green: 0.95, blue: 1.0, alpha: 1.0))
ctx.fill(CGRect(x: 0, y: pageSize.height - bandHeight, width: pageSize.width, height: bandHeight))
ctx.restoreGState()

// Logo centré
if let logoImg = NSImage(contentsOf: logoURL) {
    let logoSide: CGFloat = 200
    let logoRect = CGRect(
        x: (pageSize.width - logoSide) / 2,
        y: pageSize.height - 280,
        width: logoSide,
        height: logoSide
    )
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = nsCtx
    logoImg.draw(in: logoRect, from: .zero, operation: .sourceOver, fraction: 1.0)
    NSGraphicsContext.restoreGraphicsState()
}

// Titre
let titleFont = NSFont.systemFont(ofSize: 56, weight: .heavy)
let titleAttr = NSAttributedString(string: "MisiInfo", attributes: [
    .font: titleFont,
    .foregroundColor: cText
])
let titleSize = titleAttr.size()
titleAttr.draw(at: CGPoint(x: (pageSize.width - titleSize.width) / 2, y: pageSize.height - 380))

// Sous-titre tri-lingue
let subtitleAttr = NSAttributedString(string: "Manuel utilisateur  •  User Manual  •  Manual de usuario", attributes: [
    .font: NSFont.systemFont(ofSize: 14, weight: .medium),
    .foregroundColor: cAccent2
])
let subSize = subtitleAttr.size()
subtitleAttr.draw(at: CGPoint(x: (pageSize.width - subSize.width) / 2, y: pageSize.height - 425))

// Trait sous le sous-titre
ctx.saveGState()
ctx.setStrokeColor(cAccent.withAlphaComponent(0.3).cgColor)
ctx.setLineWidth(0.8)
let lineY = pageSize.height - 460
ctx.move(to: CGPoint(x: pageSize.width / 2 - 100, y: lineY))
ctx.addLine(to: CGPoint(x: pageSize.width / 2 + 100, y: lineY))
ctx.strokePath()
ctx.restoreGState()

// Footer credit
let footerAttr = NSAttributedString(string: "Version 1.0.0  —  2026", attributes: [
    .font: NSFont.systemFont(ofSize: 11, weight: .medium),
    .foregroundColor: cMuted
])
let footSize = footerAttr.size()
footerAttr.draw(at: CGPoint(x: (pageSize.width - footSize.width) / 2, y: 90))

let creditAttr = NSAttributedString(string: "Créé par Matthieu Misiraca  •  www.misiraca.com", attributes: [
    .font: NSFont.systemFont(ofSize: 11),
    .foregroundColor: cMuted
])
let credSize = creditAttr.size()
creditAttr.draw(at: CGPoint(x: (pageSize.width - credSize.width) / 2, y: 70))

endPage()

// MARK: - Contenu trilingue

struct Section {
    let title: String
    let body: String?
    let bullets: [String]?

    init(_ title: String, body: String? = nil, bullets: [String]? = nil) {
        self.title = title
        self.body = body
        self.bullets = bullets
    }
}

struct Manual {
    let h1: String
    let sections: [Section]
}

let frManual = Manual(h1: "Manuel utilisateur — Français", sections: [
    Section("Introduction", body: "MisiInfo est une application macOS native d'analyse technique de fichiers audio et vidéo, conçue pour les professionnels de l'audiovisuel : monteurs, chefs opérateurs, étalonneurs, ingénieurs du son, DIT, assistants monteurs, enseignants et étudiants. Glissez un fichier dans la fenêtre et MisiInfo affiche en quelques secondes toutes ses caractéristiques techniques avec une interface lisible, sans bruit, et avec un niveau de détail ajustable."),
    Section("Installation", bullets: [
        "Téléchargez le fichier MisiInfo.dmg depuis https://github.com/misilab/MisiInfo/releases/latest",
        "Double-cliquez le DMG pour l'ouvrir",
        "Glissez MisiInfo dans le dossier Applications",
        "Lancez l'application depuis le Launchpad ou Spotlight"
    ]),
    Section("Premier lancement", body: "À l'ouverture, MisiInfo affiche un écran d'accueil. Glissez un fichier audio ou vidéo dans la fenêtre, ou utilisez le bouton + dans la barre d'outils (raccourci ⌘O). Le fichier apparaît dans la liste à gauche, et son analyse complète à droite. La sidebar dispose d'une barre de recherche pour filtrer rapidement la liste lorsque vous analysez plusieurs fichiers, et un footer affiche le nombre total de fichiers et la taille cumulée."),
    Section("Sections d'analyse", bullets: [
        "Résumé : nom du fichier, conteneur, taille, durée, débit global, encodeur, caméra",
        "Vidéo : codec, profil/level, résolution, fréquence d'images, débit, sous-échantillonnage, mode de compression",
        "Colorimétrie : primaries, fonction de transfert, matrice, plage de couleurs, HDR (MaxCLL, MaxFALL, MDCV)",
        "Audio : codec, profil exact, canaux, disposition positionnelle, échantillonnage, quantification",
        "Timecode : timecode de départ et de fin SMPTE, drop frame, fréquence",
        "Pistes et flux : nombre de pistes vidéo, audio, sous-titres, présence du timecode",
        "Métadonnées : titre, artiste, dates, application d'écriture, métadonnées de caméra",
        "Détails fichier (mode Expert) : chemin, UTI Apple, brand MP4 majeur, brands compatibles",
        "MediaInfo avancé : Format Profile, Codec ID, Encoded Library, mode du débit CBR/VBR…"
    ]),
    Section("Mode Simple / Expert", body: "MisiInfo propose deux modes d'affichage que vous pouvez basculer depuis la barre d'outils. Le mode Simple n'affiche que les informations essentielles utiles à la majorité des utilisateurs. Le mode Expert dévoile tous les champs techniques, y compris les métadonnées de piste, le dump complet MediaInfo, et les détails de fichier de bas niveau."),
    Section("Timecode SMPTE", body: "MisiInfo extrait le timecode de la piste TMCD intégrée du fichier (présent sur les rushes ARRI, RED, Sony FX, Blackmagic et la plupart des fichiers professionnels). Le drop frame est automatiquement détecté avec la syntaxe SMPTE correcte (HH:MM:SS;FF pour drop frame, HH:MM:SS:FF sinon). Si le fichier n'a pas de piste TMCD, MisiInfo calcule un timecode synthétique de 00:00:00:00 à la durée."),
    Section("MediaInfo avancé", body: "La bibliothèque MediaInfoLib est embarquée dans MisiInfo (licence BSD-2-Clause). Elle apporte des informations que macOS ne fournit pas en natif : nom exact de l'encodeur (x264, x265…), application d'écriture, mode du débit (CBR / VBR / VBR with avg), Format Profile détaillé, Codec ID complet, Reference Frames, GOP, Stream Size, Compression Ratio, et beaucoup d'autres champs format-spécifiques visibles en mode Expert."),
    Section("Vignette et waveform", body: "Lorsque vous analysez un fichier vidéo, MisiInfo extrait automatiquement la première image (à 1 seconde) et l'affiche dans l'en-tête du rapport à la place du logo. Les pistes audio affichent une forme d'onde visuelle dans la section Audio. Aucune action requise — c'est automatique."),
    Section("Mesure de loudness BS.1770-4", body: "MisiInfo mesure la loudness intégrée selon la norme ITU-R BS.1770-4 : filtre K-weighting (high-shelf 1681 Hz + high-pass 38 Hz), blocs de 400 ms avec 75 % d'overlap, gating absolu à −70 LUFS puis gating relatif à −10 LU sous la moyenne. La valeur LUFS et le True Peak en dBTP s'affichent dans la section Audio. Référence broadcast EBU R128 : −23 LUFS ± 1 LU."),
    Section("Tooltips pédagogiques", body: "Au survol des termes techniques marqués d'une petite icône ⓘ, une bulle d'aide explique le concept. Plus de 30 termes sont documentés en français, anglais et espagnol : codec, profil/level, primaries, fonction de transfert, sous-échantillonnage, drop frame, LFE, etc. Outil pédagogique pour les étudiants et les techniciens en formation."),
    Section("Export du rapport", body: "Trois boutons dans l'en-tête du détail permettent de : (1) révéler le fichier source dans le Finder, (2) copier le rapport complet dans le presse-papier, (3) exporter le rapport en .txt OU en .pdf à l'emplacement de votre choix. Le PDF inclut la vignette du premier frame, la waveform audio, toutes les données techniques et la section MediaInfo avancé."),
    Section("Langue de l'interface", body: "L'interface est disponible en français, anglais et espagnol. Cliquez le drapeau dans la barre d'outils pour basculer instantanément. La langue est persistée entre les lancements."),
    Section("Mises à jour automatiques", body: "MisiInfo intègre Sparkle, le framework standard macOS pour les mises à jour. À chaque ouverture, l'application vérifie automatiquement si une nouvelle version est disponible. Quand une mise à jour existe, une alerte s'affiche avec les release notes et un bouton « Installer ». En un clic, MisiInfo télécharge la nouvelle version, vérifie sa signature Ed25519, remplace l'ancienne version dans le dossier Applications et redémarre — sans intervention manuelle. Vous pouvez aussi déclencher la vérification depuis le menu MisiInfo → Vérifier les mises à jour, ou le bouton circulaire dans la barre d'outils."),
    Section("Support et contributions", body: "MisiInfo est un logiciel libre. Signalements de bugs, demandes de fonctionnalités et contributions sont les bienvenus sur https://github.com/misilab/MisiInfo. L'auteur est joignable sur www.misiraca.com.")
])

let enManual = Manual(h1: "User Manual — English", sections: [
    Section("Introduction", body: "MisiInfo is a native macOS application for technical analysis of audio and video files, designed for audiovisual professionals: editors, cinematographers, colorists, sound engineers, DITs, assistant editors, teachers and students. Drop a file into the window and MisiInfo displays all its technical characteristics in seconds with a clean, focused interface and adjustable level of detail."),
    Section("Installation", bullets: [
        "Download the MisiInfo.dmg file from https://github.com/misilab/MisiInfo/releases/latest",
        "Double-click the DMG to open it",
        "Drag MisiInfo into the Applications folder",
        "Launch the app from Launchpad or Spotlight"
    ]),
    Section("First launch", body: "On first launch, MisiInfo shows a welcome screen. Drop an audio or video file into the window, or use the + button in the toolbar (shortcut ⌘O). The file appears in the left sidebar and its full analysis on the right. The sidebar includes a search bar to quickly filter the list when you are analyzing multiple files, and a footer shows the total file count and combined size."),
    Section("Analysis sections", bullets: [
        "Summary: file name, container, size, duration, overall bitrate, encoder, camera",
        "Video: codec, profile/level, resolution, frame rate, bitrate, chroma subsampling, compression mode",
        "Colorimetry: primaries, transfer function, matrix, color range, HDR (MaxCLL, MaxFALL, MDCV)",
        "Audio: codec, exact profile, channels, positional layout, sample rate, bit depth",
        "Timecode: SMPTE start and end timecode, drop frame, frame rate",
        "Tracks & streams: video, audio and subtitle track counts, timecode presence",
        "Metadata: title, artist, dates, writing application, camera metadata",
        "File details (Expert mode): path, Apple UTI, major MP4 brand, compatible brands",
        "Advanced MediaInfo: Format Profile, Codec ID, Encoded Library, CBR/VBR bitrate mode…"
    ]),
    Section("Simple / Expert mode", body: "MisiInfo offers two display modes you can switch from the toolbar. Simple mode shows only the essential information useful to most users. Expert mode reveals every technical field including per-track metadata, the full MediaInfo dump and low-level file details."),
    Section("SMPTE timecode", body: "MisiInfo extracts timecode from the embedded TMCD track of the file (present in ARRI, RED, Sony FX, Blackmagic dailies and most professional files). Drop frame is automatically detected with the correct SMPTE syntax (HH:MM:SS;FF for drop frame, HH:MM:SS:FF otherwise). If the file has no TMCD track, MisiInfo computes a synthetic timecode from 00:00:00:00 to the duration."),
    Section("Advanced MediaInfo", body: "The MediaInfoLib library is embedded in MisiInfo (BSD-2-Clause license). It provides information macOS does not expose natively: exact encoder name (x264, x265…), writing application, bitrate mode (CBR / VBR / VBR with avg), detailed Format Profile, full Codec ID, Reference Frames, GOP, Stream Size, Compression Ratio, and many other format-specific fields visible in Expert mode."),
    Section("Thumbnail and waveform", body: "When analyzing a video file, MisiInfo automatically extracts the first frame (at 1 second) and displays it in the report header instead of the logo. Audio tracks show a visual waveform in the Audio section. Fully automatic, no action required."),
    Section("Loudness measurement BS.1770-4", body: "MisiInfo measures integrated loudness following ITU-R BS.1770-4: K-weighting filter (high-shelf 1681 Hz + high-pass 38 Hz), 400 ms blocks with 75% overlap, absolute gating at −70 LUFS then relative gating at −10 LU below the mean. The LUFS value and True Peak in dBTP appear in the Audio section. EBU R128 broadcast reference: −23 LUFS ± 1 LU."),
    Section("Pedagogical tooltips", body: "Hovering over technical terms marked with a small ⓘ icon shows an explanatory bubble. More than 30 terms are documented in French, English and Spanish: codec, profile/level, primaries, transfer function, chroma subsampling, drop frame, LFE, etc. A teaching tool for students and trainees."),
    Section("Exporting the report", body: "Three buttons in the detail header let you: (1) reveal the source file in Finder, (2) copy the full report to the clipboard, (3) export the report as a .txt or .pdf file. The PDF includes the first-frame thumbnail, the audio waveform, all technical data and the advanced MediaInfo section."),
    Section("Interface language", body: "The interface is available in French, English and Spanish. Click the flag in the toolbar to switch instantly. Your language choice persists across launches."),
    Section("Automatic updates", body: "MisiInfo integrates Sparkle, the standard macOS framework for software updates. The app checks for new releases every time it launches. When an update is available, a native alert appears with release notes and an « Install » button. In one click, MisiInfo downloads the new version, verifies its Ed25519 signature, replaces the previous version in the Applications folder and relaunches — fully automatic. You can also trigger a check from MisiInfo → Check for Updates or the circular button in the toolbar."),
    Section("Support and contributions", body: "MisiInfo is open source. Bug reports, feature requests and contributions are welcome at https://github.com/misilab/MisiInfo. The author can be reached at www.misiraca.com.")
])

let esManual = Manual(h1: "Manual de usuario — Español", sections: [
    Section("Introducción", body: "MisiInfo es una aplicación nativa de macOS para el análisis técnico de archivos de audio y vídeo, diseñada para profesionales del sector audiovisual: editores, directores de fotografía, coloristas, ingenieros de sonido, DITs, asistentes de edición, docentes y estudiantes. Arrastre un archivo a la ventana y MisiInfo mostrará en segundos todas sus características técnicas con una interfaz limpia y un nivel de detalle ajustable."),
    Section("Instalación", bullets: [
        "Descargue el archivo MisiInfo.dmg desde https://github.com/misilab/MisiInfo/releases/latest",
        "Haga doble clic en el DMG para abrirlo",
        "Arrastre MisiInfo a la carpeta Aplicaciones",
        "Inicie la aplicación desde el Launchpad o Spotlight"
    ]),
    Section("Primer inicio", body: "Al abrirse, MisiInfo muestra una pantalla de bienvenida. Arrastre un archivo de audio o vídeo a la ventana, o use el botón + de la barra de herramientas (atajo ⌘O). El archivo aparece en la lista de la izquierda, y su análisis completo a la derecha. La barra lateral incluye un campo de búsqueda para filtrar rápidamente la lista al analizar varios archivos, y un pie de página muestra el número total de archivos y el tamaño combinado."),
    Section("Secciones de análisis", bullets: [
        "Resumen: nombre del archivo, contenedor, tamaño, duración, tasa global, codificador, cámara",
        "Vídeo: códec, perfil/nivel, resolución, frecuencia de imagen, tasa, submuestreo, modo de compresión",
        "Colorimetría: primarios, función de transferencia, matriz, rango de color, HDR (MaxCLL, MaxFALL, MDCV)",
        "Audio: códec, perfil exacto, canales, disposición posicional, frecuencia de muestreo, cuantificación",
        "Timecode: timecode de inicio y fin SMPTE, drop frame, frecuencia",
        "Pistas y flujos: número de pistas de vídeo, audio, subtítulos, presencia de timecode",
        "Metadatos: título, artista, fechas, aplicación de escritura, metadatos de cámara",
        "Detalles del archivo (modo Experto): ruta, UTI de Apple, marca principal MP4, marcas compatibles",
        "MediaInfo avanzado: Format Profile, Codec ID, Encoded Library, modo de tasa CBR/VBR…"
    ]),
    Section("Modo Simple / Experto", body: "MisiInfo ofrece dos modos de visualización que puede cambiar desde la barra de herramientas. El modo Simple muestra solo la información esencial útil para la mayoría de usuarios. El modo Experto revela todos los campos técnicos, incluidos los metadatos por pista, el volcado completo de MediaInfo y los detalles de archivo de bajo nivel."),
    Section("Timecode SMPTE", body: "MisiInfo extrae el timecode de la pista TMCD integrada en el archivo (presente en rushes de ARRI, RED, Sony FX, Blackmagic y la mayoría de archivos profesionales). El drop frame se detecta automáticamente con la sintaxis SMPTE correcta (HH:MM:SS;FF para drop frame, HH:MM:SS:FF en otro caso). Si el archivo no tiene pista TMCD, MisiInfo calcula un timecode sintético de 00:00:00:00 a la duración."),
    Section("MediaInfo avanzado", body: "La biblioteca MediaInfoLib está integrada en MisiInfo (licencia BSD-2-Clause). Aporta información que macOS no expone de forma nativa: nombre exacto del codificador (x264, x265…), aplicación de escritura, modo de tasa (CBR / VBR / VBR with avg), Format Profile detallado, Codec ID completo, Reference Frames, GOP, Stream Size, Compression Ratio, y muchos otros campos específicos de formato visibles en modo Experto."),
    Section("Miniatura y forma de onda", body: "Al analizar un archivo de vídeo, MisiInfo extrae automáticamente la primera imagen (a 1 segundo) y la muestra en la cabecera del informe en lugar del logo. Las pistas de audio muestran una forma de onda visual en la sección Audio. Totalmente automático."),
    Section("Medición de sonoridad BS.1770-4", body: "MisiInfo mide la sonoridad integrada según la norma ITU-R BS.1770-4: filtro K-weighting (high-shelf 1681 Hz + high-pass 38 Hz), bloques de 400 ms con 75 % de superposición, gating absoluto a −70 LUFS y luego gating relativo a −10 LU por debajo de la media. El valor LUFS y el True Peak en dBTP aparecen en la sección Audio. Referencia broadcast EBU R128: −23 LUFS ± 1 LU."),
    Section("Tooltips pedagógicos", body: "Al pasar el cursor sobre términos técnicos marcados con un pequeño icono ⓘ, aparece una burbuja explicativa. Más de 30 términos están documentados en francés, inglés y español: códec, perfil/nivel, primarios, función de transferencia, submuestreo de croma, drop frame, LFE, etc. Una herramienta didáctica para estudiantes y técnicos en formación."),
    Section("Exportación del informe", body: "Tres botones en la cabecera del detalle permiten: (1) mostrar el archivo de origen en el Finder, (2) copiar el informe completo al portapapeles, (3) exportar el informe como archivo .txt o .pdf en la ubicación que elija. El PDF incluye la miniatura del primer frame, la forma de onda de audio, todos los datos técnicos y la sección MediaInfo avanzada."),
    Section("Idioma de la interfaz", body: "La interfaz está disponible en francés, inglés y español. Haga clic en la bandera de la barra de herramientas para cambiar al instante. Su elección de idioma se conserva entre sesiones."),
    Section("Actualizaciones automáticas", body: "MisiInfo integra Sparkle, el framework estándar de macOS para actualizaciones. Al abrir la aplicación, se verifica automáticamente si hay una nueva versión disponible. Cuando hay actualización, aparece una alerta nativa con las notas de versión y un botón « Instalar ». Con un solo clic, MisiInfo descarga la nueva versión, verifica su firma Ed25519, reemplaza la versión anterior en la carpeta Aplicaciones y se reinicia — sin intervención manual. También puede iniciar una verificación desde MisiInfo → Buscar actualizaciones o el botón circular de la barra de herramientas."),
    Section("Soporte y contribuciones", body: "MisiInfo es software libre. Informes de errores, solicitudes de funciones y contribuciones son bienvenidas en https://github.com/misilab/MisiInfo. El autor está disponible en www.misiraca.com.")
])

func renderManual(_ m: Manual) {
    newPage()
    drawBlock(m.h1, attributes: h1Attrs)
    drawSeparator()

    for sec in m.sections {
        drawBlock(sec.title, attributes: h2Attrs, spaceBefore: 6)
        if let body = sec.body {
            drawBlock(body, attributes: bodyAttrs)
        }
        if let bullets = sec.bullets {
            for b in bullets {
                drawBlock("•   " + b, attributes: bulletAttrs)
            }
        }
    }
}

renderManual(frManual)
renderManual(enManual)
renderManual(esManual)

endPage()
ctx.closePDF()

print("✅ PDF généré : \(outputURL.path)")
