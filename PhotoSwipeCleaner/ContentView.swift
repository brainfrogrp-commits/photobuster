import SwiftUI
import UIKit

struct ContentView: View {
    @ObservedObject var model: LibraryModel

    var body: some View {
        Group {
            switch model.access {
            case .notDetermined:
                AccessRequestView(model: model)
            case .denied:
                AccessDeniedView()
            case .full, .limited:
                SwipeScreen(model: model)
            }
        }
        .task { model.refreshAccess() }
    }
}

func openAppSettings() {
    if let url = URL(string: UIApplication.openSettingsURLString) {
        UIApplication.shared.open(url)
    }
}

struct AccessRequestView: View {
    @ObservedObject var model: LibraryModel

    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 64))
                .foregroundStyle(.tint)
            Text("Clean Up Your Photos")
                .font(.largeTitle.bold())
                .multilineTextAlignment(.center)
            Text("You'll see one random photo at a time. Swipe left to keep it. Swipe right to add it to a deletion queue. Nothing is deleted until you review the queue and confirm.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Text("The app needs full access to your photo library so it can show your photos and move the ones you choose to Recently Deleted.")
                .font(.footnote)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Spacer()
            Button {
                Task { await model.requestAccess() }
            } label: {
                Text("Allow Photo Access")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .padding(24)
    }
}

struct AccessDeniedView: View {
    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "lock.slash")
                .font(.system(size: 56))
                .foregroundStyle(.secondary)
            Text("No Photo Access")
                .font(.title.bold())
            Text("The app can't see your photos, so there's nothing to review. To use it, open Settings, tap Photos, and choose Full Access.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Spacer()
            Button {
                openAppSettings()
            } label: {
                Text("Open Settings")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .padding(24)
    }
}

/// Shown at the top of the main screen when you chose "Limited Access".
struct LimitedAccessBanner: View {
    @Binding var isDismissed: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 6) {
                Text("Limited access")
                    .font(.subheadline.bold())
                Text("You only gave access to some photos, so only those will appear. For your whole library, choose Full Access in Settings.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Button("Open Settings", action: openAppSettings)
                    .font(.footnote.bold())
            }
            Spacer(minLength: 0)
            Button {
                isDismissed = true
            } label: {
                Image(systemName: "xmark")
                    .font(.footnote.bold())
                    .foregroundStyle(.secondary)
            }
            .accessibilityLabel("Dismiss")
        }
        .padding(12)
        .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
    }
}
