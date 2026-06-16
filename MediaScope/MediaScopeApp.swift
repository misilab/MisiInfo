import SwiftUI

@main
struct MisiInfoApp: App {
    @State private var updateChecker = UpdateChecker()
    @StateObject private var sparkle = SparkleManager()

    var body: some Scene {
        WindowGroup {
            ContentView(updateChecker: updateChecker)
                .frame(minWidth: 1100, minHeight: 720)
                .environmentObject(sparkle)
        }
        .defaultSize(width: 1280, height: 800)
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(replacing: .newItem) {}

            // Item Sparkle "Rechercher les mises à jour…" (UI native macOS)
            CommandGroup(after: .appInfo) {
                Button("Vérifier les mises à jour…") {
                    sparkle.checkForUpdates()
                }
                .disabled(!sparkle.canCheck)
            }
        }
    }
}
