import Foundation
import SwiftUI
import Combine

#if canImport(Sparkle)
import Sparkle

/// Wrapper SwiftUI autour de `SPUStandardUpdaterController` (Sparkle 2.x).
/// - Affiche les alertes Sparkle natives (download, prompt, install, relaunch automatique)
/// - Vérifie automatiquement à chaque ouverture de l'app via le scheduler Sparkle
/// - Signature Ed25519 vérifiée avant install
@MainActor
final class SparkleManager: ObservableObject {
    let controller: SPUStandardUpdaterController

    init() {
        // delegate: nil → comportement par défaut Sparkle
        // userDriverDelegate: nil → UI standard avec alertes/progress
        self.controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        // Force la vérification à chaque lancement (en plus du planning automatique)
        self.controller.updater.automaticallyChecksForUpdates = true
        self.controller.updater.updateCheckInterval = 3600 * 24  // 24h max entre checks auto
    }

    /// Vérification manuelle déclenchée par le menu / la toolbar.
    func checkForUpdates() {
        controller.checkForUpdates(nil)
    }

    /// `true` si la dernière vérification est en cours.
    var canCheck: Bool {
        controller.updater.canCheckForUpdates
    }
}

#else

/// Stub utilisé tant que le package `Sparkle` n'est pas encore ajouté à la cible.
/// Permet à l'app de compiler et de tourner sans la fonctionnalité auto-update.
/// Voir `INSTALL_SPARKLE.md` pour activer.
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
