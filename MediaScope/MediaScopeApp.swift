import SwiftUI

@main
struct MisiInfoApp: App {
    @State private var updateChecker = UpdateChecker()

    var body: some Scene {
        WindowGroup {
            ContentView(updateChecker: updateChecker)
                .frame(minWidth: 1100, minHeight: 720)
        }
        .defaultSize(width: 1280, height: 800)
        .windowToolbarStyle(.unified)
        .commands {
            // Pas de New Document
            CommandGroup(replacing: .newItem) {}

            // Item "Vérifier les mises à jour…" juste après "À propos de MisiInfo"
            // dans le menu de l'app (à côté de la pomme)
            CommandGroup(after: .appInfo) {
                Button("Vérifier les mises à jour…") {
                    Task { await updateChecker.check(silent: false) }
                }
                .disabled(checkerIsBusy)
            }
        }
    }

    private var checkerIsBusy: Bool {
        if case .checking = updateChecker.state { return true }
        return false
    }
}
