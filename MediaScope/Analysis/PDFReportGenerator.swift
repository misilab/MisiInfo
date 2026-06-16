import Foundation
import AppKit
import CoreText
import CoreGraphics

/// Génère un rapport PDF richement formaté avec vignette + waveform + toutes les sections.
nonisolated enum PDFReportGenerator {

    static func generate(_ analysis: MediaAnalysis, to outputURL: URL) -> Bool {
        let pageSize = CGSize(width: 595, height: 842)  // A4
        var mediaBox = CGRect(origin: .zero, size: pageSize)
        guard let consumer = CGDataConsumer(url: outputURL as CFURL),
              let ctx = CGContext(consumer: consumer, mediaBox: &mediaBox, [
                  kCGPDFContextTitle as String: "MisiInfo – \(analysis.general.fileName)" as CFString,
                  kCGPDFContextAuthor as String: "MisiInfo" as CFString,
                  kCGPDFContextCreator as String: "MisiInfo" as CFString
              ] as CFDictionary)
        else { return false }

        let renderer = Renderer(ctx: ctx, pageSize: pageSize, mediaBox: mediaBox)
        renderer.beginPage()
        renderer.drawCover(analysis: analysis)
        renderer.newPage()
        renderer.drawSections(analysis: analysis)
        renderer.endPage()
        ctx.closePDF()
        return true
    }

    private final class Renderer {
        let ctx: CGContext
        let pageSize: CGSize
        var mediaBox: CGRect
        let nsCtx: NSGraphicsContext

        let marginX: CGFloat = 56
        let marginTop: CGFloat = 60
        let marginBottom: CGFloat = 60
        var y: CGFloat = 0
        var pageOpen = false
        var pageNumber = 0

        let cAccent = NSColor(srgbRed: 0.05, green: 0.35, blue: 0.55, alpha: 1.0)
        let cAccent2 = NSColor(srgbRed: 0.15, green: 0.50, blue: 0.70, alpha: 1.0)
        let cText = NSColor(white: 0.12, alpha: 1.0)
        let cMuted = NSColor(white: 0.40, alpha: 1.0)

        init(ctx: CGContext, pageSize: CGSize, mediaBox: CGRect) {
            self.ctx = ctx
            self.pageSize = pageSize
            self.mediaBox = mediaBox
            self.nsCtx = NSGraphicsContext(cgContext: ctx, flipped: false)
        }

        var contentWidth: CGFloat { pageSize.width - 2 * marginX }

        func beginPage() {
            var box = mediaBox
            ctx.beginPDFPage([kCGPDFContextMediaBox as String: NSData(bytes: &box, length: MemoryLayout<CGRect>.size)] as CFDictionary)
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = nsCtx
            pageOpen = true
            y = marginTop
            pageNumber += 1
            drawHeaderFooter()
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

        func drawHeaderFooter() {
            // Pas sur la couverture
            guard pageNumber > 1 else { return }
            // Bandeau cyan en haut
            ctx.saveGState()
            ctx.setFillColor(CGColor(srgbRed: 0.15, green: 0.95, blue: 1.0, alpha: 1.0))
            ctx.fill(CGRect(x: 0, y: pageSize.height - 3, width: pageSize.width, height: 3))
            ctx.restoreGState()
            // Numéro page
            let attr = NSAttributedString(string: "MisiInfo  •  \(pageNumber - 1)", attributes: [
                .font: NSFont.systemFont(ofSize: 9),
                .foregroundColor: cMuted
            ])
            let size = attr.size()
            attr.draw(at: CGPoint(x: pageSize.width - marginX - size.width, y: 30))
        }

        // MARK: - Cover

        func drawCover(analysis: MediaAnalysis) {
            // Bandeau cyan
            ctx.saveGState()
            ctx.setFillColor(CGColor(srgbRed: 0.15, green: 0.95, blue: 1.0, alpha: 1.0))
            ctx.fill(CGRect(x: 0, y: pageSize.height - 6, width: pageSize.width, height: 6))
            ctx.restoreGState()

            // En-tête : logo MisiInfo + titre "MisiInfo — Rapport d'analyse"
            let logoSize: CGFloat = 36
            let headerY = pageSize.height - 28 - logoSize  // top de l'en-tête
            if let appIcon = NSImage(named: NSImage.applicationIconName) {
                NSGraphicsContext.saveGraphicsState()
                NSGraphicsContext.current = nsCtx
                appIcon.draw(in: CGRect(x: marginX, y: headerY, width: logoSize, height: logoSize))
                NSGraphicsContext.restoreGraphicsState()
            }
            let appTitleAttr = NSAttributedString(string: "MisiInfo", attributes: [
                .font: NSFont.systemFont(ofSize: 18, weight: .heavy),
                .foregroundColor: cText
            ])
            appTitleAttr.draw(at: CGPoint(x: marginX + logoSize + 12, y: headerY + 18))
            let appSubtitleAttr = NSAttributedString(string: "Rapport d'analyse technique", attributes: [
                .font: NSFont.systemFont(ofSize: 10, weight: .medium),
                .foregroundColor: cAccent2
            ])
            appSubtitleAttr.draw(at: CGPoint(x: marginX + logoSize + 12, y: headerY + 4))

            // Date en haut à droite
            let dateAttr = NSAttributedString(string: formattedDate(Date()), attributes: [
                .font: NSFont.systemFont(ofSize: 9),
                .foregroundColor: cMuted
            ])
            let dateSize = dateAttr.size()
            dateAttr.draw(at: CGPoint(x: pageSize.width - marginX - dateSize.width, y: headerY + 4))

            y = pageSize.height - headerY + 18  // après l'en-tête

            // Trait fin sous l'en-tête
            ctx.saveGState()
            ctx.setStrokeColor(NSColor(white: 0.88, alpha: 1.0).cgColor)
            ctx.setLineWidth(0.5)
            let lineY = pageSize.height - y
            ctx.move(to: CGPoint(x: marginX, y: lineY))
            ctx.addLine(to: CGPoint(x: pageSize.width - marginX, y: lineY))
            ctx.strokePath()
            ctx.restoreGState()
            y += 16

            // Vignette du premier frame
            var posterDrawn = false
            if let posterData = analysis.videoTracks.first?.posterFrame,
               let img = NSImage(data: posterData) {
                let imgRatio = img.size.width / max(img.size.height, 1)
                let drawW = min(contentWidth, 320)
                let drawH = drawW / max(imgRatio, 0.0001)
                let drawY = pageSize.height - y - drawH
                let rect = CGRect(x: (pageSize.width - drawW) / 2, y: drawY, width: drawW, height: drawH)
                NSGraphicsContext.saveGraphicsState()
                NSGraphicsContext.current = nsCtx
                ctx.saveGState()
                let path = CGPath(roundedRect: rect, cornerWidth: 8, cornerHeight: 8, transform: nil)
                ctx.addPath(path)
                ctx.clip()
                img.draw(in: rect)
                ctx.restoreGState()
                NSGraphicsContext.restoreGraphicsState()
                y += drawH + 16
                posterDrawn = true
            }
            if !posterDrawn { y += 16 }

            // Titre = nom fichier
            drawText(analysis.general.fileName, font: NSFont.systemFont(ofSize: 22, weight: .bold), color: cText, alignment: .center, spaceAfter: 6)

            // Sous-titre = format + résumé
            let summaryLine: String
            if let v = analysis.videoTracks.first {
                summaryLine = "\(v.codecName)  •  \(v.resolutionLabel)  •  \(v.frameRateLabel)  •  \(analysis.general.containerFormat)"
            } else if let a = analysis.audioTracks.first {
                summaryLine = "\(a.codecName)  •  \(a.channelsLabel)  •  \(a.sampleRateLabel)  •  \(analysis.general.containerFormat)"
            } else {
                summaryLine = analysis.general.containerFormat
            }
            drawText(summaryLine, font: NSFont.systemFont(ofSize: 12, weight: .medium), color: cAccent2, alignment: .center, spaceAfter: 20)

            // Stats clés en grille 4 colonnes
            let stats: [(String, String)] = [
                ("Durée", analysis.general.durationFormatted),
                ("Taille", analysis.general.fileSizeFormatted),
                ("Débit", analysis.general.overallBitrateFormatted ?? "—"),
                ("Conteneur", analysis.general.containerExtension)
            ]
            drawStatsRow(stats)

            // Waveform si dispo
            if let a = analysis.audioTracks.first, let peaks = a.waveformPeaks, !peaks.isEmpty {
                y += 24
                drawText("Forme d'onde audio", font: NSFont.systemFont(ofSize: 11, weight: .semibold), color: cMuted, spaceAfter: 4)
                drawWaveform(peaks: peaks, height: 60)
                if let lufs = a.integratedLUFS {
                    y += 4
                    let lufsLine = String(format: "Loudness intégrée : %.1f LUFS", lufs)
                    drawText(lufsLine, font: NSFont.systemFont(ofSize: 10), color: cMuted, alignment: .center)
                }
            }

            // Footer cover
            let creditAttr = NSAttributedString(string: "Rapport généré par MisiInfo  •  \(formattedDate(Date()))", attributes: [
                .font: NSFont.systemFont(ofSize: 9),
                .foregroundColor: cMuted
            ])
            let credSize = creditAttr.size()
            creditAttr.draw(at: CGPoint(x: (pageSize.width - credSize.width) / 2, y: 50))
        }

        // MARK: - Sections (page 2+)

        func drawSections(analysis: MediaAnalysis) {
            drawHeading("Détail technique", level: 1)

            // Résumé général
            drawHeading("Général", level: 2)
            drawKV("Nom du fichier", analysis.general.fileName)
            drawKV("Conteneur", analysis.general.containerFormat)
            drawKV("Taille", analysis.general.fileSizeFormatted)
            drawKV("Durée", analysis.general.durationFormatted)
            drawKV("Débit global", analysis.general.overallBitrateFormatted ?? "—")
            if let enc = analysis.general.encoder { drawKV("Encodeur", enc) }
            if let cam = analysis.general.writingApplication { drawKV("Caméra / Application", cam) }
            drawKV("UTI", analysis.general.utiType ?? "—")

            for (idx, v) in analysis.videoTracks.enumerated() {
                drawHeading("Vidéo \(idx + 1)", level: 2)
                drawKV("Codec", "\(v.codecName) (\(v.codecFourCC))")
                drawKV("Nom long du codec", v.codecLongName ?? "—")
                drawKV("Profil / Level", v.codecProfile ?? "—")
                drawKV("Résolution encodée", v.resolutionLabel)
                drawKV("Résolution d'affichage", v.displayResolutionLabel)
                drawKV("Ratio d'aspect", v.aspectRatioLabel)
                drawKV("Pixel aspect ratio", v.pixelAspectRatio.map { String(format: "%.3f", $0) } ?? "—")
                drawKV("Fréquence d'images", v.frameRateLabel)
                drawKV("Mode du débit images", v.frameRateMode ?? "—")
                drawKV("Débit estimé", v.bitrateLabel ?? "—")
                drawKV("Ordre des trames", v.fieldOrder ?? "—")
                drawKV("Espace de couleurs", v.colorSpace ?? "—")
                drawKV("Mode de compression", v.compressionMode ?? "—")
                // Champs Expert
                drawKV("Profondeur par composante", v.bitDepth.map { "\($0) bits" } ?? "—")
                drawKV("Sous-échantillonnage", v.chromaSubsampling ?? "—")
                drawKV("Pixel format", v.pixelFormat ?? "—")
                drawKV("Nombre total de frames", v.totalFrames.map { "\($0)" } ?? "—")
                drawKV("Bits / (Pixel × Image)", v.bitsPerPixelFrame.map { String(format: "%.3f", $0) } ?? "—")
                drawKV("Taille moyenne par frame", v.averageFrameSize.map {
                    ByteCountFormatter.string(fromByteCount: $0, countStyle: .file)
                } ?? "—")
                drawKV("Durée de la piste", v.trackDuration.map { String(format: "%.3f s", $0) } ?? "—")
                drawKV("Track ID", "\(v.trackID)")
                if let mfd = v.minFrameDuration {
                    drawKV("Durée min. de frame", String(format: "%.6f s", mfd))
                }
                if !v.trackMetadata.isEmpty {
                    drawHeading("Métadonnées de piste vidéo", level: 3)
                    for item in v.trackMetadata { drawKV(item.key, item.value) }
                }

                drawHeading("Colorimétrie", level: 3)
                drawKV("Primaries (gamut)", v.colorPrimaries ?? "—")
                drawKV("Fonction de transfert", v.transferFunction ?? "—")
                drawKV("Matrice YCbCr", v.yCbCrMatrix ?? "—")
                drawKV("Plage de couleurs", v.colorRange ?? "—")
                drawKV("HDR", v.isHDR ? (v.hdrFormat ?? "Oui") : "Non")
                if v.isHDR {
                    if let cll = v.maxCLL { drawKV("MaxCLL", "\(cll) nits") }
                    if let fall = v.maxFALL { drawKV("MaxFALL", "\(fall) nits") }
                    drawKV("Mastering Display Color Volume", v.hasMasteringDisplay ? "Présent" : "Absent")
                }
            }

            for (idx, a) in analysis.audioTracks.enumerated() {
                drawHeading("Audio \(idx + 1)", level: 2)
                drawKV("Codec", "\(a.codecName) (\(a.codecFourCC))")
                drawKV("Codec ID détaillé", a.codecIDLong ?? "—")
                drawKV("Profil audio", a.audioProfile ?? "—")
                drawKV("Canaux", a.channelsLabel)
                drawKV("Disposition des canaux", a.channelMap ?? "—")
                drawKV("Fréquence d'échantillonnage", a.sampleRateLabel)
                drawKV("Quantification", a.bitsPerChannel.map { "\($0) bits" } ?? "—")
                drawKV("Débit estimé", a.bitrateLabel ?? "—")
                drawKV("Format", a.isCompressed ? "Compressé" : "PCM non compressé")
                if !a.isCompressed { drawKV("Endianness", a.endianness ?? "—") }
                if let lufs = a.integratedLUFS {
                    drawKV("Loudness intégrée (LUFS, BS.1770-4)", String(format: "%.1f LUFS", lufs))
                }
                if let tp = a.truePeakDBTP {
                    drawKV("Crête vraie (dBTP)", String(format: "%.1f dBTP", tp))
                }
                // Champs Expert
                drawKV("Échantillons par frame", a.samplesPerFrame.map { "\($0) SPF" } ?? "—")
                drawKV("Nombre total d'échantillons", a.totalSamples.map { "\($0)" } ?? "—")
                drawKV("Durée de la piste", a.trackDuration.map { String(format: "%.3f s", $0) } ?? "—")
                drawKV("Langue", a.language ?? "—")
                drawKV("Track ID", "\(a.trackID)")

                if !a.trackMetadata.isEmpty {
                    drawHeading("Métadonnées de piste audio", level: 3)
                    for item in a.trackMetadata { drawKV(item.key, item.value) }
                }

                if let peaks = a.waveformPeaks, !peaks.isEmpty {
                    y += 6
                    drawWaveform(peaks: peaks, height: 40)
                }
            }

            // Sous-titres
            if !analysis.subtitleTracks.isEmpty {
                drawHeading("Sous-titres / Closed Captions", level: 2)
                for (idx, s) in analysis.subtitleTracks.enumerated() {
                    drawKV("Piste \(idx + 1)", "\(s.format)\(s.language.map { " (\($0))" } ?? "")\(s.isClosedCaption ? " — CC" : "")")
                }
            }

            // Timecode
            drawHeading("Timecode", level: 2)
            if let tc = analysis.timecode {
                drawKV("Source", "Piste TMCD intégrée")
                drawKV("Timecode de départ", tc.startTimecode ?? "—")
                drawKV("Timecode de fin", tc.endTimecode ?? "—")
                drawKV("Fréquence", String(format: "%.3f fps", tc.frameRate))
                drawKV("Drop frame", tc.dropFrame ? "Oui" : "Non")
                drawKV("Track ID", "\(tc.trackID)")
            } else {
                drawKV("Source", "Calculé depuis la durée (pas de piste TMCD)")
            }

            // Pistes et flux
            drawHeading("Pistes et flux", level: 2)
            drawKV("Pistes vidéo", "\(analysis.videoTracks.count)")
            drawKV("Pistes audio", "\(analysis.audioTracks.count)")
            drawKV("Sous-titres / CC", "\(analysis.subtitleTracks.count)")
            drawKV("Timecode", analysis.timecode != nil ? "Présent" : "Absent")

            // Métadonnées globales
            if !analysis.metadata.isEmpty {
                drawHeading("Métadonnées", level: 2)
                for item in analysis.metadata {
                    let prefix = item.keySpace.map { "[\($0)] " } ?? ""
                    drawKV("\(prefix)\(item.key)", item.value)
                }
            }

            // MediaInfo avancé
            if let mi = analysis.mediaInfo, !mi.isEmpty {
                drawHeading("MediaInfo avancé", level: 2)
                drawKV("Format", mi.format ?? "—")
                drawKV("Format / Profil", mi.formatProfile ?? "—")
                drawKV("Codec ID (MediaInfo)", mi.codecID ?? "—")
                drawKV("Encoded Library", mi.encodedLibrary ?? "—")
                drawKV("Writing application", mi.writingApplication ?? "—")
                drawKV("Writing library", mi.writingLibrary ?? "—")
                drawKV("Mode du débit", mi.bitRateMode ?? "—")
                drawKV("Stream size", mi.streamSize ?? "—")
                drawKV("Reference frames", mi.referenceFrames ?? "—")
                drawKV("Format Level", mi.formatLevel ?? "—")
                drawKV("Chroma subsampling (MediaInfo)", mi.chromaSubsampling ?? "—")
                drawKV("Scan type", mi.scanType ?? "—")
                drawKV("Scan order", mi.scanOrder ?? "—")
                drawKV("Compression ratio", mi.compressionRatio ?? "—")
                if !mi.extraVideo.isEmpty {
                    drawHeading("MediaInfo — Vidéo (tous champs)", level: 3)
                    for (k, v) in mi.extraVideo.sorted(by: { $0.key < $1.key }) { drawKV(k, v) }
                }
                if !mi.extraAudio.isEmpty {
                    drawHeading("MediaInfo — Audio (tous champs)", level: 3)
                    for (k, v) in mi.extraAudio.sorted(by: { $0.key < $1.key }) { drawKV(k, v) }
                }
                if !mi.extraGeneral.isEmpty {
                    drawHeading("MediaInfo — Général (tous champs)", level: 3)
                    for (k, v) in mi.extraGeneral.sorted(by: { $0.key < $1.key }) { drawKV(k, v) }
                }
            }

            // Détails fichier
            drawHeading("Détails fichier", level: 2)
            drawKV("Chemin complet", analysis.general.fileURL.path)
            drawKV("Extension", analysis.general.containerExtension)
            drawKV("UTI", analysis.general.utiType ?? "—")
            drawKV("Marque majeure (ftyp)", analysis.general.majorBrand ?? "—")
            if !analysis.general.compatibleBrands.isEmpty {
                drawKV("Marques compatibles", analysis.general.compatibleBrands.joined(separator: ", "))
            }
            if let c = analysis.general.creationDate {
                drawKV("Date de création", formattedDate(c))
            }
            if let m = analysis.general.modificationDate {
                drawKV("Date de modification", formattedDate(m))
            }
        }

        // MARK: - Drawing helpers

        func ensure(_ height: CGFloat) {
            if y + height > pageSize.height - marginBottom { newPage() }
        }

        func drawText(_ text: String, font: NSFont, color: NSColor, alignment: NSTextAlignment = .left, spaceAfter: CGFloat = 6, indent: CGFloat = 0) {
            let style = NSMutableParagraphStyle()
            style.alignment = alignment
            style.lineSpacing = 2
            let attrs: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: color,
                .paragraphStyle: style
            ]
            let attr = NSAttributedString(string: text, attributes: attrs)
            let framesetter = CTFramesetterCreateWithAttributedString(attr as CFAttributedString)
            let width = contentWidth - indent
            let suggested = CTFramesetterSuggestFrameSizeWithConstraints(framesetter, CFRange(location: 0, length: attr.length), nil, CGSize(width: width, height: .greatestFiniteMagnitude), nil)
            ensure(suggested.height + spaceAfter)
            let drawY = pageSize.height - y - suggested.height
            let path = CGPath(rect: CGRect(x: marginX + indent, y: drawY, width: width, height: suggested.height + 2), transform: nil)
            let frame = CTFramesetterCreateFrame(framesetter, CFRange(location: 0, length: attr.length), path, nil)
            CTFrameDraw(frame, ctx)
            y += suggested.height + spaceAfter
        }

        func drawHeading(_ text: String, level: Int) {
            switch level {
            case 1:
                y += 4
                drawText(text, font: NSFont.systemFont(ofSize: 20, weight: .bold), color: cAccent, spaceAfter: 10)
                drawSeparator()
            case 2:
                y += 8
                drawText(text, font: NSFont.systemFont(ofSize: 14, weight: .bold), color: cAccent2, spaceAfter: 4)
            default:
                y += 4
                drawText(text, font: NSFont.systemFont(ofSize: 11, weight: .semibold), color: cText, spaceAfter: 2)
            }
        }

        func drawKV(_ k: String, _ v: String) {
            let style = NSMutableParagraphStyle()
            style.lineSpacing = 2
            let kAttr = NSAttributedString(string: k, attributes: [
                .font: NSFont.systemFont(ofSize: 9.5),
                .foregroundColor: cMuted,
                .paragraphStyle: style
            ])
            let vAttr = NSAttributedString(string: v, attributes: [
                .font: NSFont.systemFont(ofSize: 9.5, weight: .medium),
                .foregroundColor: cText,
                .paragraphStyle: style
            ])
            let kw: CGFloat = 200
            let vw = contentWidth - kw - 8
            let kFs = CTFramesetterCreateWithAttributedString(kAttr as CFAttributedString)
            let vFs = CTFramesetterCreateWithAttributedString(vAttr as CFAttributedString)
            let kSize = CTFramesetterSuggestFrameSizeWithConstraints(kFs, CFRange(location: 0, length: kAttr.length), nil, CGSize(width: kw, height: .greatestFiniteMagnitude), nil)
            let vSize = CTFramesetterSuggestFrameSizeWithConstraints(vFs, CFRange(location: 0, length: vAttr.length), nil, CGSize(width: vw, height: .greatestFiniteMagnitude), nil)
            let height = max(kSize.height, vSize.height)
            ensure(height + 3)
            let drawY = pageSize.height - y - height
            let kPath = CGPath(rect: CGRect(x: marginX, y: drawY, width: kw, height: height + 2), transform: nil)
            let vPath = CGPath(rect: CGRect(x: marginX + kw + 8, y: drawY, width: vw, height: height + 2), transform: nil)
            CTFrameDraw(CTFramesetterCreateFrame(kFs, CFRange(location: 0, length: kAttr.length), kPath, nil), ctx)
            CTFrameDraw(CTFramesetterCreateFrame(vFs, CFRange(location: 0, length: vAttr.length), vPath, nil), ctx)
            y += height + 3
        }

        func drawSeparator() {
            ensure(10)
            let drawY = pageSize.height - y - 4
            ctx.saveGState()
            ctx.setStrokeColor(NSColor(white: 0.85, alpha: 1.0).cgColor)
            ctx.setLineWidth(0.5)
            ctx.move(to: CGPoint(x: marginX, y: drawY))
            ctx.addLine(to: CGPoint(x: pageSize.width - marginX, y: drawY))
            ctx.strokePath()
            ctx.restoreGState()
            y += 10
        }

        func drawStatsRow(_ stats: [(String, String)]) {
            ensure(60)
            let drawY = pageSize.height - y - 50
            let col = contentWidth / CGFloat(stats.count)
            for (i, s) in stats.enumerated() {
                let x = marginX + CGFloat(i) * col
                let titleAttr = NSAttributedString(string: s.0.uppercased(), attributes: [
                    .font: NSFont.systemFont(ofSize: 8, weight: .semibold),
                    .foregroundColor: cMuted,
                    .kern: 0.5
                ])
                let valueAttr = NSAttributedString(string: s.1, attributes: [
                    .font: NSFont.systemFont(ofSize: 16, weight: .bold),
                    .foregroundColor: cText
                ])
                let tw = titleAttr.size().width
                let vw = valueAttr.size().width
                titleAttr.draw(at: CGPoint(x: x + (col - tw) / 2, y: drawY + 26))
                valueAttr.draw(at: CGPoint(x: x + (col - vw) / 2, y: drawY))
            }
            y += 50
        }

        func drawWaveform(peaks: [Float], height: CGFloat) {
            ensure(height + 8)
            let drawY = pageSize.height - y - height
            let rect = CGRect(x: marginX, y: drawY, width: contentWidth, height: height)
            ctx.saveGState()
            ctx.setFillColor(NSColor(srgbRed: 0.10, green: 0.50, blue: 0.85, alpha: 0.08).cgColor)
            ctx.fill(rect)
            ctx.setFillColor(NSColor(srgbRed: 0.10, green: 0.50, blue: 0.85, alpha: 0.85).cgColor)
            let mid = drawY + height / 2
            let barW = rect.width / CGFloat(peaks.count)
            for (i, p) in peaks.enumerated() {
                let amp = max(1, CGFloat(p) * height)
                let x = marginX + CGFloat(i) * barW
                ctx.fill(CGRect(x: x, y: mid - amp / 2, width: max(0.5, barW * 0.75), height: amp))
            }
            ctx.restoreGState()
            y += height + 8
        }

        func formattedDate(_ d: Date) -> String {
            let f = DateFormatter()
            f.dateStyle = .medium
            f.timeStyle = .short
            return f.string(from: d)
        }
    }
}
