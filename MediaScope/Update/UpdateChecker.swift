import Foundation
import Observation
import SwiftUI

/// Détecte les nouvelles releases publiées sur GitHub via l'API publique.
/// Aucun token requis tant que la limite de 60 requêtes/heure/IP n'est pas atteinte
/// (largement suffisant : l'app check une fois par 24h).
///
/// Pour activer : renseigne `repoPath` ci-dessous au format "owner/repo".
nonisolated enum UpdateConfig {
    /// Repo GitHub au format "owner/repo".
    static let repoPath = "misilab/MisiInfo"
    /// Nom de l'asset DMG attendu dans la release (sinon on prend le 1er .dmg trouvé).
    static let preferredAssetName = "MisiInfo.dmg"
}

/// Réponse partielle de l'API GitHub `/repos/:owner/:repo/releases/latest`.
nonisolated struct GitHubRelease: Decodable, Sendable, Hashable {
    let tagName: String
    let name: String?
    let body: String?
    let htmlURL: URL
    let prerelease: Bool
    let draft: Bool
    let assets: [Asset]

    struct Asset: Decodable, Sendable, Hashable {
        let name: String
        let browserDownloadURL: URL

        enum CodingKeys: String, CodingKey {
            case name
            case browserDownloadURL = "browser_download_url"
        }
    }

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case name
        case body
        case htmlURL = "html_url"
        case prerelease
        case draft
        case assets
    }

    /// Version "1.0.1" extraite du tag "v1.0.1" / "1.0.1". Strip prefix uniquement.
    var version: String {
        var t = tagName.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.hasPrefix("v") || t.hasPrefix("V") { t.removeFirst() }
        return t
    }

    /// `true` si la version est de la forme `1`, `1.2`, `1.2.3`, `1.2.3.4` (numérique uniquement).
    /// Évite que des tags non-semver (`release-123`, `beta-2`) déclenchent une comparaison absurde.
    var isSemver: Bool {
        let v = version
        guard !v.isEmpty else { return false }
        return v.range(of: "^\\d+(\\.\\d+)*$", options: .regularExpression) != nil
    }

    /// URL de téléchargement préférée (DMG) ou page de release par défaut.
    var downloadURL: URL {
        if let dmg = assets.first(where: { $0.name == UpdateConfig.preferredAssetName }) {
            return dmg.browserDownloadURL
        }
        if let anyDmg = assets.first(where: { $0.name.lowercased().hasSuffix(".dmg") }) {
            return anyDmg.browserDownloadURL
        }
        return htmlURL
    }
}

nonisolated enum UpdateState: Sendable, Equatable {
    case idle
    case checking
    case upToDate
    case available(GitHubRelease)
    case failed(String)

    static func == (lhs: UpdateState, rhs: UpdateState) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle), (.checking, .checking), (.upToDate, .upToDate): return true
        case (.available(let a), .available(let b)): return a == b
        case (.failed(let a), .failed(let b)): return a == b
        default: return false
        }
    }
}

@Observable
final class UpdateChecker {
    var state: UpdateState = .idle

    private let lastCheckKey = "MisiInfo.lastUpdateCheck"

    var currentVersion: String {
        (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "0.0"
    }

    /// URL de l'API GitHub. Si le `repoPath` contient des caractères invalides, on revient
    /// vers une URL bidon pour éviter un crash (le check retournera `.failed`).
    var apiURL: URL {
        let encoded = UpdateConfig.repoPath.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? ""
        return URL(string: "https://api.github.com/repos/\(encoded)/releases/latest")
            ?? URL(string: "https://api.github.com/")!
    }

    /// Évite plusieurs checks simultanés (l'utilisateur qui spamme le bouton).
    private var inFlight = false

    /// Check silencieux au lancement à chaque ouverture de l'app.
    func checkAutomaticallyAtLaunch() {
        Task { await check(silent: true) }
    }

    func check(silent: Bool = false) async {
        if inFlight { return }
        inFlight = true
        defer { inFlight = false }

        await MainActor.run { self.state = .checking }
        do {
            var request = URLRequest(url: apiURL)
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            request.setValue("MisiInfo", forHTTPHeaderField: "User-Agent")
            request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
            request.timeoutInterval = 10

            let cfg = URLSessionConfiguration.ephemeral
            cfg.timeoutIntervalForRequest = 10
            cfg.timeoutIntervalForResource = 30
            let session = URLSession(configuration: cfg)

            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                throw URLError(.badServerResponse)
            }
            let release = try JSONDecoder().decode(GitHubRelease.self, from: data)
            UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: lastCheckKey)

            // Filtrage : prereleases, brouillons et tags non-semver sont traités comme "à jour"
            guard !release.prerelease, !release.draft, release.isSemver else {
                await MainActor.run { self.state = silent ? .idle : .upToDate }
                return
            }

            let newer = isNewer(release.version, than: currentVersion)
            await MainActor.run {
                if newer {
                    self.state = .available(release)
                } else {
                    self.state = silent ? .idle : .upToDate
                }
            }
        } catch {
            await MainActor.run {
                self.state = silent ? .idle : .failed(error.localizedDescription)
            }
        }
    }

    /// Compare deux versions semver composant par composant après padding avec des zéros.
    /// `1.0.0` == `1.0` == `1`, et `1.0.1` > `1.0` correctement.
    private func isNewer(_ candidate: String, than base: String) -> Bool {
        let a = candidate.split(separator: ".").compactMap { Int($0) }
        let b = base.split(separator: ".").compactMap { Int($0) }
        let len = max(a.count, b.count)
        let pa = a + Array(repeating: 0, count: len - a.count)
        let pb = b + Array(repeating: 0, count: len - b.count)
        for i in 0..<len {
            if pa[i] > pb[i] { return true }
            if pa[i] < pb[i] { return false }
        }
        return false
    }
}
