import Photos
import UIKit

/// Loads one photo's image, downloading it from iCloud when needed.
@MainActor
final class PhotoLoader: ObservableObject {
    static let cachingManager = PHCachingImageManager()
    /// Big enough for a full-screen photo on any iPhone.
    static let fullSize = CGSize(width: 1290, height: 2796)
    static let thumbnailSize = CGSize(width: 360, height: 360)

    static func fullOptions() -> PHImageRequestOptions {
        let options = PHImageRequestOptions()
        options.deliveryMode = .opportunistic
        options.resizeMode = .fast
        options.isNetworkAccessAllowed = true
        return options
    }

    @Published private(set) var image: UIImage?
    @Published private(set) var isLoading = false
    /// Download progress from iCloud, 0...1, or nil when not downloading.
    @Published private(set) var downloadProgress: Double?
    @Published private(set) var failed = false

    private var requestID: PHImageRequestID?
    private var loadedID: String?

    func load(_ asset: PHAsset, size: CGSize, contentMode: PHImageContentMode) {
        guard loadedID != asset.localIdentifier else { return }
        cancel()
        loadedID = asset.localIdentifier
        image = nil
        failed = false
        downloadProgress = nil
        isLoading = true

        let options = Self.fullOptions()
        // PhotoKit calls these on background threads, so they hop to the main actor.
        options.progressHandler = { @Sendable [weak self] progress, _, _, _ in
            Task { @MainActor in
                guard let self, self.isLoading else { return }
                self.downloadProgress = progress
            }
        }

        let id = asset.localIdentifier
        requestID = Self.cachingManager.requestImage(
            for: asset,
            targetSize: size,
            contentMode: contentMode,
            options: options
        ) { @Sendable [weak self] result, info in
            let isDegraded = (info?[PHImageResultIsDegradedKey] as? Bool) ?? false
            let isCancelled = (info?[PHImageCancelledKey] as? Bool) ?? false
            let hasError = info?[PHImageErrorKey] != nil
            Task { @MainActor in
                guard let self, self.loadedID == id, !isCancelled else { return }
                if let result { self.image = result }
                // A low-quality preview may arrive first; keep waiting for the real one.
                if isDegraded && !hasError { return }
                self.isLoading = false
                self.downloadProgress = nil
                if result == nil || (hasError && self.image == nil) {
                    self.failed = true
                }
            }
        }
    }

    func cancel() {
        if let requestID { Self.cachingManager.cancelImageRequest(requestID) }
        requestID = nil
        loadedID = nil
    }
}
