import Foundation

/// Deliberately `ObservableObject` + `@Published`, not `@Observable` — the latter
/// is iOS 17+ only, and this app targets iOS 16.
@MainActor
final class TrackerViewModel: ObservableObject {
    @Published private(set) var modes: [String: ModeFile] = [:]
    @Published private(set) var isRefreshing = false
    @Published var refreshError: String?

    private let dataService: DataService
    private var progress: [String: Int] = [:]
    private var completed: Set<String> = []

    private let progressKey = "mw4_progress_v1"

    init(dataService: DataService = DataService()) {
        self.dataService = dataService
        loadProgress()
        for mode in ["multiplayer", "campaign", "dmz"] {
            modes[mode] = dataService.loadCached(mode: mode) ?? dataService.loadSeed(mode: mode)
        }
    }

    /// Checks the CDN manifest and pulls only the mode files whose version changed.
    func refresh() async {
        isRefreshing = true
        defer { isRefreshing = false }
        do {
            let known = modes.mapValues { $0.version }
            let updated = try await dataService.refreshIfNeeded(knownVersions: known)
            for (mode, file) in updated { modes[mode] = file }
            refreshError = nil
        } catch {
            refreshError = error.localizedDescription
        }
    }

    // MARK: - Progress

    func amount(mode: String, categoryId: Int, itemId: Int) -> Int {
        progress[key(mode, categoryId, itemId)] ?? 0
    }

    func isComplete(mode: String, categoryId: Int, item: ChallengeItem) -> Bool {
        guard let req = item.requirement else {
            return completed.contains(key(mode, categoryId, item.itemId))
        }
        return amount(mode: mode, categoryId: categoryId, itemId: item.itemId) >= req.amount
    }

    func setAmount(mode: String, categoryId: Int, item: ChallengeItem, amount newAmount: Int) {
        let req = item.requirement?.amount ?? 1
        progress[key(mode, categoryId, item.itemId)] = max(0, min(newAmount, req))
        saveProgress()
        objectWillChange.send()
    }

    func toggleComplete(mode: String, categoryId: Int, item: ChallengeItem) {
        let k = key(mode, categoryId, item.itemId)
        if let req = item.requirement {
            let isDone = amount(mode: mode, categoryId: categoryId, itemId: item.itemId) >= req.amount
            progress[k] = isDone ? 0 : req.amount
        } else if completed.contains(k) {
            completed.remove(k)
        } else {
            completed.insert(k)
        }
        saveProgress()
        objectWillChange.send()
    }

    // MARK: - Aggregate progress (recursive over children — same code for a weapon's
    // camos or a DMZ objective's tiers, since both are just `ChallengeItem` trees)

    func progressFraction(of item: ChallengeItem, mode: String, categoryId: Int) -> Double {
        fraction(of: leafItems(of: item), mode: mode, categoryId: categoryId)
    }

    func progressFraction(of category: Category, mode: String) -> Double {
        fraction(of: category.items.flatMap(leafItems), mode: mode, categoryId: category.categoryId)
    }

    private func fraction(of leaves: [ChallengeItem], mode: String, categoryId: Int) -> Double {
        guard !leaves.isEmpty else { return 0 }
        let done = leaves.filter { isComplete(mode: mode, categoryId: categoryId, item: $0) }.count
        return Double(done) / Double(leaves.count)
    }

    private func leafItems(of item: ChallengeItem) -> [ChallengeItem] {
        item.isLeaf ? [item] : item.children.flatMap(leafItems)
    }

    // MARK: - Persistence

    private func key(_ mode: String, _ categoryId: Int, _ itemId: Int) -> String {
        "\(mode)|\(categoryId)|\(itemId)"
    }

    private func loadProgress() {
        guard let data = UserDefaults.standard.data(forKey: progressKey),
              let store = try? JSONDecoder().decode(ProgressStore.self, from: data) else { return }
        progress = store.amounts
        completed = Set(store.completed)
    }

    private func saveProgress() {
        let store = ProgressStore(amounts: progress, completed: Array(completed))
        if let data = try? JSONEncoder().encode(store) {
            UserDefaults.standard.set(data, forKey: progressKey)
        }
    }
}

private struct ProgressStore: Codable {
    var amounts: [String: Int]
    var completed: [String]
}
