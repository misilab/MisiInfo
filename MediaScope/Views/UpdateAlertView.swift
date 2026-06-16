import SwiftUI

struct UpdateAlertModifier: ViewModifier {
    @Bindable var checker: UpdateChecker

    func body(content: Content) -> some View {
        content
            .alert("Nouvelle version disponible", isPresented: showAvailableBinding, presenting: availableRelease) { release in
                Button("Télécharger") {
                    NSWorkspace.shared.open(release.downloadURL)
                    checker.state = .idle
                }
                Button("Voir sur GitHub") {
                    NSWorkspace.shared.open(release.htmlURL)
                    checker.state = .idle
                }
                Button("Plus tard", role: .cancel) {
                    checker.state = .idle
                }
            } message: { release in
                VStack(alignment: .leading, spacing: 6) {
                    Text("MisiInfo \(release.version) est disponible (vous avez \(checker.currentVersion)).")
                    if let body = release.body, !body.isEmpty {
                        Text(body.prefix(400) + (body.count > 400 ? "…" : ""))
                            .font(.callout)
                    }
                }
            }
            .alert("À jour", isPresented: showUpToDateBinding) {
                Button("OK", role: .cancel) { checker.state = .idle }
            } message: {
                Text("MisiInfo \(checker.currentVersion) est la dernière version.")
            }
            .alert("Vérification impossible", isPresented: showFailedBinding) {
                Button("OK", role: .cancel) { checker.state = .idle }
            } message: {
                if case .failed(let msg) = checker.state {
                    Text(msg)
                }
            }
    }

    private var availableRelease: GitHubRelease? {
        if case .available(let r) = checker.state { return r }
        return nil
    }

    private var showAvailableBinding: Binding<Bool> {
        Binding(
            get: { if case .available = checker.state { return true } else { return false } },
            set: { newValue in if !newValue { checker.state = .idle } }
        )
    }

    private var showUpToDateBinding: Binding<Bool> {
        Binding(
            get: { if case .upToDate = checker.state { return true } else { return false } },
            set: { newValue in if !newValue { checker.state = .idle } }
        )
    }

    private var showFailedBinding: Binding<Bool> {
        Binding(
            get: { if case .failed = checker.state { return true } else { return false } },
            set: { newValue in if !newValue { checker.state = .idle } }
        )
    }
}

extension View {
    func updateAlerts(_ checker: UpdateChecker) -> some View {
        modifier(UpdateAlertModifier(checker: checker))
    }
}
