import Foundation
import SwiftUI
import Combine

#if canImport(Sparkle)
import Sparkle

/// Wrapper SwiftUI autour de `SPUStandardUpdaterController` (Sparkle 2.x).
@MainActor
final class SparkleManager: NSObject, ObservableObject, SPUUpdaterDelegate {
    let controller: SPUStandardUpdaterController

    /// URL de l'appcast (fournie programmatiquement via le delegate, pas via Info.plist).
    static let feedURL = "https://raw.githubusercontent.com/misilab/MisiInfo/main/docs/appcast.xml"

    /// Clé publique Ed25519 (utilisée par Sparkle pour vérifier les signatures).
    /// Doit aussi être présente dans Info.plist sous `SUPublicEDKey` pour que Sparkle l'utilise.
    /// Voir le Run Script build phase dans INSTALL_SPARKLE.md.
    static let publicEDKey = "bxP11zE5Pla4VRO1J3UhVM3TRD4WUFdkKNDPWFWjU/I="

    override init() {
        // L'instance temporaire pour avoir une ref vers self avant l'init du controller
        let dummyDelegate: SPUUpdaterDelegate? = nil
        self.controller = SPUStandardUpdaterController(
            startingUpdater: false,
            updaterDelegate: dummyDelegate,
            userDriverDelegate: nil
        )
        super.init()
        // On wire le delegate après super.init pour avoir self valide
        self.controller.updater.setValue(self, forKey: "delegate")
        self.controller.startUpdater()
        self.controller.updater.automaticallyChecksForUpdates = true
        self.controller.updater.updateCheckInterval = 3600 * 24
    }

    func checkForUpdates() {
        controller.checkForUpdates(nil)
    }

    var canCheck: Bool {
        controller.updater.canCheckForUpdates
    }

    // MARK: - SPUUpdaterDelegate

    /// Fournit l'URL de l'appcast à Sparkle (alternative à `SUFeedURL` dans Info.plist).
    func feedURLString(for updater: SPUUpdater) -> String? {
        SparkleManager.feedURL
    }
}

#else

@MainActor
final class SparkleManager: ObservableObject {
    init() {}

    func checkForUpdates() {
        let alert = NSAlert()
        alert.messageText = "Sparkle non installé"
        alert.informativeText = "L'auto-update Sparkle n'est pas encore branché dans ce build. "
            + "Voir INSTALL_SPARKLE.md à la racine du projet."
        alert.runModal()
    }

    var canCheck: Bool { false }
}

#endif
