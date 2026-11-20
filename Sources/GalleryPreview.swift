import SwiftUI

struct GalleryPreview: View {
    let item: WallItem
    @State private var image: CGImage?
    @State private var failure: String?
    @State private var attempt = 0

    var body: some View {
        Group {
            if let image {
                Image(image, scale: 1, label: Text("壁纸大图"))
                    .resizable()
                    .scaledToFit()
            } else if let failure {
                ContentUnavailableView {
                    Label("无法打开大图", systemImage: "photo.badge.exclamationmark")
                } description: {
                    Text(failure)
                } actions: {
                    Button("重试") {
                        self.failure = nil
                        attempt += 1
                    }
                    .buttonStyle(.bordered)
                }
            } else {
                ProgressView("正在载入大图…")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle("壁纸预览")
        .navigationSubtitle(item.resolution ?? "")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarVisibility(.hidden, for: .tabBar)
        .toolbar {
            if let image {
                ToolbarItem(placement: .primaryAction) {
                    let picture = Image(decorative: image, scale: 1)
                    ShareLink(item: picture, preview: SharePreview("映壁壁纸", image: picture)) {
                        Label("分享图片", systemImage: "square.and.arrow.up")
                    }
                }
            }
        }
        .task(id: attempt) {
            guard image == nil else { return }
            do {
                let result = try await GalleryImages.shared.read(item.full, maxPixel: nil)
                try Task.checkCancellation()
                image = result
            } catch {
                if !Task.isCancelled { failure = error.localizedDescription }
            }
        }
    }
}
