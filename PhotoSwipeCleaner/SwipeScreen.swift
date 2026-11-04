import Photos
import SwiftUI
import UIKit

struct SwipeScreen: View {
    @ObservedObject var model: LibraryModel
    @State private var showReview = false
    @State private var limitedBannerDismissed = false

    var body: some View {
        VStack(spacing: 12) {
            if model.access == .limited && !limitedBannerDismissed {
                LimitedAccessBanner(isDismissed: $limitedBannerDismissed)
            }

            ProgressHeader(remaining: model.remainingCount, queued: model.queuedCount, skipped: model.skippedCount)

            ZStack {
                if let asset = model.current {
                    SwipeCard(
                        asset: asset,
                        onKeep: { model.keepCurrent() },
                        onDelete: { model.queueCurrent() },
                        onLoadFailed: { model.skipCurrentAfterLoadFailure(asset) }
                    )
                    .id(asset.localIdentifier)
                    .transition(.opacity)
                } else if !model.hasLoadedOnce || model.isLoadingLibrary {
                    ProgressView("Loading your library…")
                } else {
                    FinishedView(model: model, showReview: $showReview)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            HStack(spacing: 12) {
                Button {
                    withAnimation(.easeOut(duration: 0.15)) { model.undo() }
                } label: {
                    Label("Undo", systemImage: "arrow.uturn.backward")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(!model.canUndo)

                Button {
                    showReview = true
                } label: {
                    Label("Review & Delete (\(model.queuedCount))", systemImage: "trash")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .disabled(model.queuedCount == 0)
            }
            .controlSize(.large)
        }
        .padding(16)
        .sheet(isPresented: $showReview) {
            ReviewView(model: model)
        }
    }
}

struct ProgressHeader: View {
    let remaining: Int
    let queued: Int
    let skipped: Int

    var body: some View {
        VStack(spacing: 4) {
            HStack {
                Label("\(remaining) left", systemImage: "photo.stack")
                Spacer()
                Label("\(queued) queued", systemImage: "trash")
                    .foregroundStyle(queued > 0 ? Color.red : Color.secondary)
            }
            .font(.subheadline.monospacedDigit())
            HStack {
                Text("← Keep")
                    .foregroundStyle(.green)
                Spacer()
                if skipped > 0 {
                    Text("\(skipped) couldn't load")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text("Delete →")
                    .foregroundStyle(.red)
            }
            .font(.caption.bold())
        }
    }
}

struct FinishedView: View {
    @ObservedObject var model: LibraryModel
    @Binding var showReview: Bool

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(.green)
            Text("All Done")
                .font(.title.bold())
            Text("You've reviewed every photo in your library.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)

            if model.queuedCount > 0 {
                Text("You still have \(model.queuedCount) photo\(model.queuedCount == 1 ? "" : "s") waiting in the deletion queue.")
                    .multilineTextAlignment(.center)
                Button("Review & Delete") { showReview = true }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
            }

            if model.skippedCount > 0 {
                Text("\(model.skippedCount) photo\(model.skippedCount == 1 ? "" : "s") couldn't be loaded, probably because they're in iCloud and the download failed. They haven't been marked as reviewed.")
                    .font(.footnote)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                Button("Try Those Again") { model.retrySkipped() }
                    .buttonStyle(.bordered)
            }
        }
        .padding()
    }
}

/// One photo that follows your finger. Left keeps it, right queues it for deletion.
struct SwipeCard: View {
    let asset: PHAsset
    let onKeep: () -> Void
    let onDelete: () -> Void
    let onLoadFailed: () -> Void

    @StateObject private var loader = PhotoLoader()
    @State private var offset: CGSize = .zero
    @State private var isCommitting = false

    /// How far you have to drag before letting go counts as a decision.
    private let threshold: CGFloat = 110

    var body: some View {
        GeometryReader { geo in
            ZStack {
                RoundedRectangle(cornerRadius: 20)
                    .fill(Color(.secondarySystemBackground))

                if let image = loader.image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                }

                if loader.isLoading {
                    VStack(spacing: 8) {
                        ProgressView()
                        if let progress = loader.downloadProgress {
                            Text("Downloading from iCloud… \(Int(progress * 100))%")
                                .font(.caption)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(.thinMaterial, in: Capsule())
                        }
                    }
                }

                decisionLabel
            }
            .clipShape(RoundedRectangle(cornerRadius: 20))
            .offset(x: offset.width, y: offset.height * 0.25)
            .rotationEffect(.degrees(Double(offset.width / 25)), anchor: .bottom)
            .gesture(dragGesture(cardWidth: geo.size.width))
            .allowsHitTesting(loader.image != nil && !isCommitting)
            .onAppear {
                loader.load(asset, size: PhotoLoader.fullSize, contentMode: .aspectFit)
            }
        }
        .onDisappear { loader.cancel() }
        .onChange(of: loader.failed) { _, failed in
            if failed { onLoadFailed() }
        }
        .sensoryFeedback(.impact(weight: .light), trigger: pastThreshold) { _, newValue in newValue != 0 }
    }

    /// -1 when a release would keep, 1 when it would delete, 0 otherwise.
    private var pastThreshold: Int {
        if offset.width <= -threshold { return -1 }
        if offset.width >= threshold { return 1 }
        return 0
    }

    @ViewBuilder
    private var decisionLabel: some View {
        let progress = min(abs(offset.width) / threshold, 1)
        if offset.width < 0 {
            stamp("KEEP", color: .green)
                .opacity(progress)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                .padding(24)
        } else if offset.width > 0 {
            stamp("DELETE", color: .red)
                .opacity(progress)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(24)
        }
    }

    private func stamp(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: 40, weight: .heavy, design: .rounded))
            .foregroundStyle(color)
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(color, lineWidth: 4))
    }

    private func dragGesture(cardWidth: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 10)
            .onChanged { value in
                guard !isCommitting else { return }
                offset = value.translation
            }
            .onEnded { value in
                guard !isCommitting else { return }
                let dx = value.translation.width
                let flick = value.predictedEndTranslation.width
                // A long drag, or a quick flick that's already well on its way, counts.
                if dx <= -threshold || (flick <= -threshold * 2.5 && dx < -40) {
                    fling(direction: -1, cardWidth: cardWidth)
                } else if dx >= threshold || (flick >= threshold * 2.5 && dx > 40) {
                    fling(direction: 1, cardWidth: cardWidth)
                } else {
                    // A short swipe snaps back and does nothing.
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        offset = .zero
                    }
                }
            }
    }

    private func fling(direction: CGFloat, cardWidth: CGFloat) {
        isCommitting = true
        withAnimation(.easeIn(duration: 0.18)) {
            offset = CGSize(width: direction * cardWidth * 1.6, height: offset.height)
        } completion: {
            if direction < 0 { onKeep() } else { onDelete() }
        }
    }
}
