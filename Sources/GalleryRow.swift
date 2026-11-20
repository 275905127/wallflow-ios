import SwiftUI

struct GalleryRow: View {
    let item: WallItem
    let name: String
    let isRandom: Bool
    let transition: Namespace.ID

    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        VStack(alignment: .leading) {
            GalleryThumbnail(url: item.thumb)
                .aspectRatio(isRandom ? 3.0 / 4.0 : 16.0 / 9.0, contentMode: .fit)
                .matchedTransitionSource(id: item.id, in: transition)
                .accessibilityHidden(true)

            if let resolution = item.resolution {
                if typeSize.isAccessibilitySize {
                    Text(name).font(.headline)
                    Text(verbatim: resolution).font(.subheadline).foregroundStyle(.secondary)
                } else {
                    LabeledContent {
                        Text(verbatim: resolution).font(.subheadline).foregroundStyle(.secondary)
                    } label: {
                        Text(name).font(.headline)
                    }
                }
            } else {
                Text(name).font(.headline)
            }
        }
        .frame(maxWidth: 600)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
    }
}

private struct GalleryThumbnail: View {
    let url: URL
    @State private var image: CGImage?
    @State private var failed = false

    var body: some View {
        Rectangle()
            .fill(.quaternary)
            .overlay {
                if let image {
                    Image(decorative: image, scale: 1).resizable().scaledToFill()
                } else if failed {
                    Image(systemName: "photo.badge.exclamationmark")
                        .imageScale(.large)
                        .foregroundStyle(.secondary)
                } else {
                    ProgressView()
                }
            }
            .clipped()
            .clipShape(.rect(cornerRadius: 12))
            .task(id: url) {
                image = nil
                failed = false
                do {
                    image = try await GalleryImages.shared.read(url, maxPixel: 960)
                } catch {
                    if !Task.isCancelled { failed = true }
                }
            }
    }
}
