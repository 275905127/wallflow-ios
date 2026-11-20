import Foundation
import ImageIO

// Decode off the main actor. Keep full-size images for the system share sheet.
actor GalleryImages {
    static let shared = GalleryImages()

    func read(_ url: URL, maxPixel: Int?) async throws -> CGImage {
        try Task.checkCancellation()
        let source: CGImageSource?
        if url.isFileURL {
            source = CGImageSourceCreateWithURL(url as CFURL, nil)
        } else {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                throw URLError(.badServerResponse)
            }
            source = CGImageSourceCreateWithData(data as CFData, nil)
        }
        try Task.checkCancellation()
        guard let source else { throw URLError(.cannotDecodeContentData) }
        var options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true
        ]
        if let maxPixel { options[kCGImageSourceThumbnailMaxPixelSize] = maxPixel }
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            throw URLError(.cannotDecodeContentData)
        }
        try Task.checkCancellation()
        return image
    }
}
