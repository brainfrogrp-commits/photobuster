import Foundation

/// The decisions you have made, saved on the device.
///
/// Photos are tracked by their PhotoKit local identifier. The file lives in the
/// app's Application Support folder, which iOS keeps when you reinstall the app
/// over itself with the same bundle ID.
final class DecisionStore {
    private struct SavedState: Codable {
        var accepted: [String]
        var queued: [String]
    }

    private(set) var accepted: Set<String> = []
    /// Queued photos, oldest first.
    private(set) var queued: [String] = []
    private var queuedSet: Set<String> = []

    private let fileURL: URL
    private let ioQueue = DispatchQueue(label: "PhotoSwipeCleaner.DecisionStore", qos: .utility)

    init() {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("decisions.json")

        if let data = try? Data(contentsOf: fileURL),
           let state = try? JSONDecoder().decode(SavedState.self, from: data) {
            accepted = Set(state.accepted)
            queued = state.queued
            queuedSet = Set(state.queued)
        }
    }

    // MARK: Queries

    var queuedCount: Int { queued.count }

    func isReviewed(_ id: String) -> Bool {
        accepted.contains(id) || queuedSet.contains(id)
    }

    func isQueued(_ id: String) -> Bool {
        queuedSet.contains(id)
    }

    /// Everything you have already decided on, for filtering the library.
    func reviewedSnapshot() -> Set<String> {
        accepted.union(queuedSet)
    }

    // MARK: Changes (each one is saved right away)

    func accept(_ id: String) {
        accepted.insert(id)
        save()
    }

    func unaccept(_ id: String) {
        accepted.remove(id)
        save()
    }

    func enqueue(_ id: String) {
        guard queuedSet.insert(id).inserted else { return }
        queued.append(id)
        save()
    }

    func dequeue(_ ids: Set<String>) {
        guard !ids.isEmpty else { return }
        queued.removeAll { ids.contains($0) }
        queuedSet.subtract(ids)
        save()
    }

    /// Takes a photo out of the deletion queue and marks it as kept.
    func moveFromQueueToAccepted(_ id: String) {
        queued.removeAll { $0 == id }
        queuedSet.remove(id)
        accepted.insert(id)
        save()
    }

    // MARK: Saving

    private func save() {
        let state = SavedState(accepted: Array(accepted), queued: queued)
        let url = fileURL
        // Writes run in order on a background queue so swiping stays smooth.
        ioQueue.async {
            guard let data = try? JSONEncoder().encode(state) else { return }
            try? data.write(to: url, options: .atomic)
        }
    }

    /// Blocks until pending writes finish. Called when the app goes to the background.
    func flush() {
        ioQueue.sync {}
    }
}
