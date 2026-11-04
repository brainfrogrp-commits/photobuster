import Photos
import SwiftUI

/// Holds the app's state: photo access, the photo on screen, and your decisions.
@MainActor
final class LibraryModel: NSObject, ObservableObject {
    enum Access {
        case notDetermined
        case full
        case limited
        case denied
    }

    private enum Decision {
        case kept(String)
        case queued(String)
    }

    @Published private(set) var access: Access
    @Published private(set) var current: PHAsset?
    @Published private(set) var isLoadingLibrary = false
    @Published private(set) var hasLoadedOnce = false
    @Published private(set) var remainingCount = 0
    @Published private(set) var queuedCount = 0
    @Published private(set) var skippedCount = 0
    @Published private(set) var canUndo = false

    let store = DecisionStore()

    /// Identifiers of photos not yet reviewed, excluding `current` and `upcoming`.
    private var pool: [String] = []
    /// The next photo, picked early so its image can be cached before you see it.
    private var upcoming: PHAsset?
    /// Photos that failed to load this session. They are not marked as reviewed.
    private var skipped: Set<String> = []
    private var history: [Decision] = []
    private let historyLimit = 200

    private var observingLibrary = false
    private var reloadTask: Task<Void, Never>?
    private var loadGeneration = 0

    override init() {
        access = Self.currentAccess()
        super.init()
        queuedCount = store.queuedCount
    }

    // MARK: Access

    private static func currentAccess() -> Access {
        switch PHPhotoLibrary.authorizationStatus(for: .readWrite) {
        case .notDetermined: return .notDetermined
        case .authorized: return .full
        case .limited: return .limited
        case .denied, .restricted: return .denied
        @unknown default: return .denied
        }
    }

    func requestAccess() async {
        _ = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        refreshAccess()
    }

    /// Re-checks access. Called at launch and whenever the app comes back to the
    /// foreground, because you may have changed it in Settings.
    func refreshAccess() {
        let newAccess = Self.currentAccess()
        let changed = newAccess != access
        access = newAccess

        guard newAccess == .full || newAccess == .limited else { return }
        if !observingLibrary {
            PHPhotoLibrary.shared().register(self)
            observingLibrary = true
            reloadLibrary()
        } else if changed {
            reloadLibrary()
        }
    }

    // MARK: Loading the library

    /// Lists the identifiers of every image (no videos) and keeps the ones you
    /// haven't reviewed. Only identifiers are kept in memory, never images, so
    /// this copes with tens of thousands of photos.
    func reloadLibrary() {
        loadGeneration += 1
        let generation = loadGeneration
        let reviewed = store.reviewedSnapshot()
        isLoadingLibrary = true

        Task.detached(priority: .userInitiated) {
            let options = PHFetchOptions()
            options.predicate = NSPredicate(format: "mediaType == %d", PHAssetMediaType.image.rawValue)
            options.includeHiddenAssets = false
            let result = PHAsset.fetchAssets(with: options)

            var unreviewed: [String] = []
            unreviewed.reserveCapacity(result.count)
            var all = Set<String>(minimumCapacity: result.count)
            result.enumerateObjects { asset, _, _ in
                let id = asset.localIdentifier
                all.insert(id)
                if !reviewed.contains(id) { unreviewed.append(id) }
            }
            let ids = unreviewed
            let existing = all

            await MainActor.run {
                self.finishReload(generation: generation, unreviewed: ids, existing: existing)
            }
        }
    }

    private func finishReload(generation: Int, unreviewed: [String], existing: Set<String>) {
        guard generation == loadGeneration else { return }

        // Drop queued photos that were deleted some other way (for example in the Photos app).
        let missingFromQueue = Set(store.queued.filter { !existing.contains($0) })
        store.dequeue(missingFromQueue)
        if !missingFromQueue.isEmpty { clearHistory() }

        if let c = current, !existing.contains(c.localIdentifier) { current = nil }
        if let u = upcoming, !existing.contains(u.localIdentifier) { upcoming = nil }

        let onScreen = Set([current?.localIdentifier, upcoming?.localIdentifier].compactMap { $0 })
        pool = unreviewed.filter { !onScreen.contains($0) && !skipped.contains($0) && !store.isReviewed($0) }
        skipped = skipped.intersection(existing)

        if current == nil { advance() } else if upcoming == nil { pickUpcoming() }

        isLoadingLibrary = false
        hasLoadedOnce = true
        updateCounts()
    }

    // MARK: Picking photos

    private func advance() {
        if let next = upcoming, !store.isReviewed(next.localIdentifier) {
            current = next
            upcoming = nil
        } else {
            upcoming = nil
            current = takeRandomFromPool()
        }
        pickUpcoming()
        updateCounts()
    }

    private func pickUpcoming() {
        guard upcoming == nil else { return }
        upcoming = takeRandomFromPool()
        if let upcoming {
            PhotoLoader.cachingManager.startCachingImages(
                for: [upcoming],
                targetSize: PhotoLoader.fullSize,
                contentMode: .aspectFit,
                options: PhotoLoader.fullOptions()
            )
        }
    }

    private func takeRandomFromPool() -> PHAsset? {
        while !pool.isEmpty {
            let index = Int.random(in: pool.indices)
            pool.swapAt(index, pool.count - 1)
            let id = pool.removeLast()
            if store.isReviewed(id) || skipped.contains(id) { continue }
            if let asset = PHAsset.fetchAssets(withLocalIdentifiers: [id], options: nil).firstObject {
                return asset
            }
        }
        return nil
    }

    private func updateCounts() {
        remainingCount = pool.count + (current == nil ? 0 : 1) + (upcoming == nil ? 0 : 1)
        queuedCount = store.queuedCount
        skippedCount = skipped.count
        canUndo = !history.isEmpty
    }

    // MARK: Decisions

    /// Swipe left: keep the photo for good.
    func keepCurrent() {
        guard let id = current?.localIdentifier else { return }
        store.accept(id)
        record(.kept(id))
        advance()
    }

    /// Swipe right: add the photo to the deletion queue. Nothing is deleted yet.
    func queueCurrent() {
        guard let id = current?.localIdentifier else { return }
        store.enqueue(id)
        record(.queued(id))
        advance()
    }

    private func record(_ decision: Decision) {
        history.append(decision)
        if history.count > historyLimit { history.removeFirst(history.count - historyLimit) }
    }

    private func clearHistory() {
        history.removeAll()
        canUndo = false
    }

    /// Reverses the last swipe and shows that photo again.
    func undo() {
        while let last = history.popLast() {
            let id: String
            switch last {
            case .kept(let keptID):
                guard store.accepted.contains(keptID) else { continue }
                store.unaccept(keptID)
                id = keptID
            case .queued(let queuedID):
                guard store.isQueued(queuedID) else { continue }
                store.dequeue([queuedID])
                id = queuedID
            }
            guard let asset = PHAsset.fetchAssets(withLocalIdentifiers: [id], options: nil).firstObject else {
                continue
            }
            // The photo that was on screen goes back to the unreviewed pile.
            if let shown = current { pool.append(shown.localIdentifier) }
            current = asset
            updateCounts()
            return
        }
        updateCounts()
    }

    /// Called when a photo can't be loaded (for example, no network for an
    /// iCloud photo). It's skipped for now but stays unreviewed.
    func skipCurrentAfterLoadFailure(_ asset: PHAsset) {
        guard current?.localIdentifier == asset.localIdentifier else { return }
        skipped.insert(asset.localIdentifier)
        advance()
    }

    /// Puts photos that failed to load back into the pile.
    func retrySkipped() {
        pool.append(contentsOf: skipped)
        skipped.removeAll()
        if current == nil { advance() } else { updateCounts() }
    }

    // MARK: Review & Delete

    func queuedAssets() -> [PHAsset] {
        let ids = store.queued
        guard !ids.isEmpty else { return [] }
        let result = PHAsset.fetchAssets(withLocalIdentifiers: ids, options: nil)
        var byID: [String: PHAsset] = [:]
        result.enumerateObjects { asset, _, _ in byID[asset.localIdentifier] = asset }

        let missing = Set(ids.filter { byID[$0] == nil })
        if !missing.isEmpty {
            store.dequeue(missing)
            clearHistory()
            updateCounts()
        }
        return ids.compactMap { byID[$0] }
    }

    /// In the review screen: take a photo out of the queue and keep it.
    func keepInsteadOfDeleting(_ id: String) {
        store.moveFromQueueToAccepted(id)
        clearHistory()
        updateCounts()
    }

    enum DeleteOutcome {
        case deleted(Int)
        case cancelled
        case failed(String)
    }

    /// Deletes every queued photo in one request. iOS asks you to confirm, and
    /// the photos go to Recently Deleted. The queue only changes if it succeeds.
    func deleteQueued() async -> DeleteOutcome {
        let ids = store.queued
        guard !ids.isEmpty else { return .deleted(0) }
        let assets = PHAsset.fetchAssets(withLocalIdentifiers: ids, options: nil)
        guard assets.count > 0 else {
            store.dequeue(Set(ids))
            updateCounts()
            return .deleted(0)
        }
        let deletedCount = assets.count

        do {
            try await Self.performDelete(ids)
            store.dequeue(Set(ids))
            clearHistory()
            updateCounts()
            return .deleted(deletedCount)
        } catch {
            if Self.isUserCancel(error) { return .cancelled }
            return .failed(error.localizedDescription)
        }
    }

    /// Runs off the main actor because PhotoKit calls the change block on its own queue.
    /// The standard change request makes iOS show its "Allow … to delete?" prompt.
    private nonisolated static func performDelete(_ ids: [String]) async throws {
        try await PHPhotoLibrary.shared().performChanges {
            let assets = PHAsset.fetchAssets(withLocalIdentifiers: ids, options: nil)
            PHAssetChangeRequest.deleteAssets(assets)
        }
    }

    private nonisolated static func isUserCancel(_ error: Error) -> Bool {
        if let photosError = error as? PHPhotosError, photosError.code == .userCancelled { return true }
        let nsError = error as NSError
        if nsError.domain == NSCocoaErrorDomain && nsError.code == NSUserCancelledError { return true }
        return nsError.domain == PHPhotosErrorDomain && nsError.code == PHPhotosError.Code.userCancelled.rawValue
    }

    // MARK: App lifecycle

    func appDidEnterBackground() {
        store.flush()
    }
}

// MARK: - Library changes

extension LibraryModel: PHPhotoLibraryChangeObserver {
    /// Photos added or deleted elsewhere (or by our own batch delete) trigger a
    /// refresh, debounced so iCloud syncing doesn't cause constant reloads.
    nonisolated func photoLibraryDidChange(_ changeInstance: PHChange) {
        Task { @MainActor in
            self.reloadTask?.cancel()
            self.reloadTask = Task { @MainActor in
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                guard !Task.isCancelled else { return }
                self.reloadLibrary()
            }
        }
    }
}
