import Photos
import SwiftUI
import UIKit

/// Lists the deletion queue. Tap a photo to keep it instead, then delete the rest at once.
struct ReviewView: View {
    @ObservedObject var model: LibraryModel
    @Environment(\.dismiss) private var dismiss

    @State private var assets: [PHAsset] = []
    @State private var isDeleting = false
    @State private var message: String?

    private let columns = [GridItem(.adaptive(minimum: 100), spacing: 4)]

    var body: some View {
        NavigationStack {
            Group {
                if assets.isEmpty {
                    emptyState
                } else {
                    ScrollView {
                        Text("Tap a photo to keep it. It will leave the queue and won't be shown again.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 16)
                            .padding(.top, 8)

                        LazyVGrid(columns: columns, spacing: 4) {
                            ForEach(assets, id: \.localIdentifier) { asset in
                                Button {
                                    keep(asset)
                                } label: {
                                    Thumbnail(asset: asset)
                                }
                                .buttonStyle(.plain)
                                .disabled(isDeleting)
                                .accessibilityLabel("Keep this photo instead")
                            }
                        }
                        .padding(4)
                    }
                    .safeAreaInset(edge: .bottom) { deleteBar }
                }
            }
            .navigationTitle("Deletion Queue (\(assets.count))")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                        .disabled(isDeleting)
                }
            }
            .alert(
                "Photos",
                isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } }),
                presenting: message
            ) { _ in
                Button("OK", role: .cancel) {}
            } message: { text in
                Text(text)
            }
        }
        .interactiveDismissDisabled(isDeleting)
        .onAppear { assets = model.queuedAssets() }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "trash.slash")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("The deletion queue is empty.")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var deleteBar: some View {
        Button(role: .destructive) {
            Task { await deleteAll() }
        } label: {
            HStack {
                if isDeleting { ProgressView().tint(.white) }
                Text(isDeleting ? "Deleting…" : "Delete \(assets.count) Photo\(assets.count == 1 ? "" : "s")")
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .tint(.red)
        .controlSize(.large)
        .disabled(isDeleting || assets.isEmpty)
        .padding(16)
        .background(.bar)
    }

    private func keep(_ asset: PHAsset) {
        model.keepInsteadOfDeleting(asset.localIdentifier)
        withAnimation {
            assets.removeAll { $0.localIdentifier == asset.localIdentifier }
        }
    }

    private func deleteAll() async {
        isDeleting = true
        let outcome = await model.deleteQueued()
        isDeleting = false
        switch outcome {
        case .deleted(let count):
            assets = model.queuedAssets()
            message = "Deleted \(count) photo\(count == 1 ? "" : "s"). You can still restore them from Recently Deleted in the Photos app for about 30 days."
        case .cancelled:
            // You tapped "Don't Allow" in the iOS prompt. Nothing was deleted and the queue is unchanged.
            assets = model.queuedAssets()
        case .failed(let reason):
            assets = model.queuedAssets()
            message = "Nothing was deleted, and your queue is unchanged.\n\n\(reason)"
        }
    }
}

/// A square thumbnail, downloaded from iCloud if needed.
struct Thumbnail: View {
    let asset: PHAsset
    @StateObject private var loader = PhotoLoader()

    var body: some View {
        Color(.secondarySystemBackground)
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                if let image = loader.image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                } else if loader.isLoading {
                    ProgressView()
                } else if loader.failed {
                    Image(systemName: "exclamationmark.icloud")
                        .foregroundStyle(.secondary)
                }
            }
            .clipped()
            .contentShape(Rectangle())
            .onAppear {
                loader.load(asset, size: PhotoLoader.thumbnailSize, contentMode: .aspectFill)
            }
            .onDisappear { loader.cancel() }
    }
}
