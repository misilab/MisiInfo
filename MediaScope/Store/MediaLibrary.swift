import Foundation
import Observation
import SwiftUI

enum ViewMode: String, CaseIterable, Identifiable {
    case simple, expert
    var id: String { rawValue }
    var label: LocalizedStringKey {
        switch self {
        case .simple: return "Vue simple"
        case .expert: return "Vue experte"
        }
    }
}

@Observable
final class MediaLibrary {
    var items: [MediaItem] = []
    var selectionID: MediaItem.ID?
    var viewMode: ViewMode = .simple

    /// Tasks d'analyse en cours, pour pouvoir les annuler sur remove/reanalyze.
    @ObservationIgnored private var tasks: [MediaItem.ID: Task<Void, Never>] = [:]

    var selectedItem: MediaItem? {
        guard let id = selectionID else { return nil }
        return items.first(where: { $0.id == id })
    }

    func add(urls: [URL]) {
        for url in urls {
            guard !items.contains(where: { $0.url == url }) else { continue }
            let item = MediaItem(url: url)
            items.append(item)
            if selectionID == nil { selectionID = item.id }
            kickoffAnalysis(itemID: item.id, url: url)
        }
    }

    func remove(itemID: MediaItem.ID) {
        tasks[itemID]?.cancel()
        tasks.removeValue(forKey: itemID)
        items.removeAll { $0.id == itemID }
        if selectionID == itemID { selectionID = items.first?.id }
    }

    func reanalyze(itemID: MediaItem.ID) {
        tasks[itemID]?.cancel()
        guard let index = items.firstIndex(where: { $0.id == itemID }) else { return }
        items[index].state = .pending
        let url = items[index].url
        kickoffAnalysis(itemID: itemID, url: url)
    }

    /// Lance l'analyse en `Task.detached` pour ne JAMAIS bloquer le MainActor.
    /// La Task est trackée dans `tasks` pour permettre l'annulation.
    private func kickoffAnalysis(itemID: MediaItem.ID, url: URL) {
        updateState(itemID: itemID, state: .analyzing)
        let task = Task.detached(priority: .userInitiated) {
            let result: MediaItem.State
            do {
                let analysis = try await MediaAnalyzer.analyze(url: url)
                if Task.isCancelled { return }
                result = .ready(analysis)
            } catch {
                if Task.isCancelled { return }
                result = .failed(error.localizedDescription)
            }
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.tasks.removeValue(forKey: itemID)
                self.updateState(itemID: itemID, state: result)
            }
        }
        tasks[itemID] = task
    }

    private func updateState(itemID: MediaItem.ID, state: MediaItem.State) {
        guard let index = items.firstIndex(where: { $0.id == itemID }) else { return }
        items[index].state = state
    }
}

struct MediaItem: Identifiable, Hashable {
    let id = UUID()
    let url: URL
    var state: State = .pending

    var displayName: String { url.lastPathComponent }
    var analysis: MediaAnalysis? {
        if case .ready(let a) = state { return a }
        return nil
    }

    enum State: Hashable {
        case pending
        case analyzing
        case ready(MediaAnalysis)
        case failed(String)
    }
}
