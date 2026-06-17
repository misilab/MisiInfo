import SwiftUI
import UniformTypeIdentifiers

enum AppLanguage: String, CaseIterable, Identifiable {
    case system, fr, en, es
    var id: String { rawValue }

    var label: LocalizedStringKey {
        switch self {
        case .system: return "Système"
        case .fr: return "Français"
        case .en: return "English"
        case .es: return "Español"
        }
    }

    /// Drapeau emoji (ou nil pour `.system` qui utilise un SF Symbol).
    var emoji: String? {
        switch self {
        case .system: return nil
        case .fr: return "🇫🇷"
        case .en: return "🇬🇧"
        case .es: return "🇪🇸"
        }
    }

    var locale: Locale? {
        switch self {
        case .system: return nil
        case .fr: return Locale(identifier: "fr")
        case .en: return Locale(identifier: "en")
        case .es: return Locale(identifier: "es")
        }
    }
}

struct ContentView: View {
    @State private var library = MediaLibrary()
    @State private var showImporter = false
    @State private var comparisonMode = false
    @State private var comparisonRightID: MediaItem.ID?

    private var readyComparisonCandidates: [MediaItem] {
        library.items.filter { $0.analysis != nil }
    }
    @Bindable var updateChecker: UpdateChecker
    @EnvironmentObject var sparkle: SparkleManager
    @AppStorage("appLanguage") private var languageRaw: String = AppLanguage.system.rawValue

    private var language: AppLanguage {
        AppLanguage(rawValue: languageRaw) ?? .system
    }

    private var updateCheckerIsChecking: Bool {
        if case .checking = updateChecker.state { return true }
        return false
    }

    var body: some View {
        NavigationSplitView {
            FileListView(library: library)
                .frame(minWidth: 260)
                .navigationSplitViewColumnWidth(min: 260, ideal: 300, max: 380)
        } detail: {
            Group {
                if comparisonMode,
                   let aID = library.selectionID,
                   let aAnalysis = library.items.first(where: { $0.id == aID })?.analysis,
                   let bID = comparisonRightID,
                   let bAnalysis = library.items.first(where: { $0.id == bID })?.analysis {
                    ComparisonView(left: aAnalysis, right: bAnalysis)
                } else {
                    AnalysisDetailView(item: library.selectedItem, mode: library.viewMode)
                }
            }
            .frame(minWidth: 560)
            .background(.background.secondary)
        }
        .navigationSplitViewStyle(.balanced)
        .environment(\.locale, language.locale ?? Locale.current)
        .navigationTitle("MisiInfo")
        .toolbar {
            ToolbarItem(placement: .navigation) {
                if library.selectedItem != nil {
                    Picker("Mode", selection: $library.viewMode) {
                        ForEach(ViewMode.allCases) { mode in
                            Text(mode.label).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 220)
                }
            }
            ToolbarItem(placement: .primaryAction) {
                if readyComparisonCandidates.count >= 2 {
                    Menu {
                        Toggle(isOn: $comparisonMode) {
                            Label("Mode comparaison", systemImage: "rectangle.split.2x1")
                        }
                        if comparisonMode {
                            Divider()
                            Text("Comparer à")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            ForEach(readyComparisonCandidates.filter { $0.id != library.selectionID }, id: \.id) { item in
                                Button {
                                    comparisonRightID = item.id
                                } label: {
                                    HStack {
                                        Text(item.displayName)
                                        if comparisonRightID == item.id {
                                            Spacer()
                                            Image(systemName: "checkmark")
                                        }
                                    }
                                }
                            }
                        }
                    } label: {
                        Label("Comparer", systemImage: "rectangle.split.2x1")
                    }
                    .help("Comparer 2 fichiers côte à côte")
                }
            }
            ToolbarItem(placement: .primaryAction) {
                languageMenu
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    sparkle.checkForUpdates()
                } label: {
                    Label("Vérifier les mises à jour", systemImage: "arrow.triangle.2.circlepath")
                }
                .help("Vérifier les mises à jour")
                .disabled(!sparkle.canCheck)
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showImporter = true
                } label: {
                    Label("Importer", systemImage: "plus")
                }
                .keyboardShortcut("o", modifiers: [.command])
                .help("Importer un fichier (⌘O)")
            }
        }
        .updateAlerts(updateChecker)
        .task {
            updateChecker.checkAutomaticallyAtLaunch()
        }
        .dropDestination(for: URL.self) { urls, _ in
            library.add(urls: urls)
            return !urls.isEmpty
        }
        .fileImporter(
            isPresented: $showImporter,
            allowedContentTypes: [.audiovisualContent, .audio, .movie, .video],
            allowsMultipleSelection: true
        ) { result in
            if case .success(let urls) = result {
                library.add(urls: urls)
            }
        }
    }

    private var languageMenu: some View {
        Menu {
            ForEach(AppLanguage.allCases) { lang in
                Button {
                    languageRaw = lang.rawValue
                } label: {
                    HStack {
                        if let emoji = lang.emoji {
                            Text(emoji)
                        } else {
                            Image(systemName: "globe")
                        }
                        Text(lang.label)
                        if lang == language {
                            Spacer()
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            if let emoji = language.emoji {
                Text(emoji).font(.title3)
            } else {
                Image(systemName: "globe")
            }
        }
        .menuStyle(.borderlessButton)
        .help("Langue de l'interface")
    }
}

#Preview {
    ContentView(updateChecker: UpdateChecker())
}
