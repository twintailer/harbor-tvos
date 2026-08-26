import ImageIO
import SwiftUI
import UIKit

/// Shared decoded-artwork cache. SwiftUI's `AsyncImage` creates a fresh decode
/// for cards as rows leave/re-enter the viewport; keeping downsampled UIImages
/// avoids those focus-scroll hitches and lowers peak memory on older Apple TVs.
actor HarborArtworkCache {
    static let shared = HarborArtworkCache()
    private let images = NSCache<NSString, UIImage>()

    init() {
        images.countLimit = 180
        images.totalCostLimit = 220 * 1024 * 1024
    }

    func image(for rawURL: String?, maxPixelSize: CGFloat = 1600) async -> UIImage? {
        guard let rawURL, let url = URL(string: rawURL), !rawURL.isEmpty else { return nil }
        let key = "\(rawURL)|\(Int(maxPixelSize))" as NSString
        if let cached = images.object(forKey: key) { return cached }

        var request = URLRequest(url: url)
        request.cachePolicy = .returnCacheDataElseLoad
        request.timeoutInterval = 20
        let data: Data
        if let cached = URLCache.shared.cachedResponse(for: request) {
            data = cached.data
        } else {
            guard let result = try? await URLSession.shared.data(for: request),
                  let http = result.1 as? HTTPURLResponse,
                  (200..<300).contains(http.statusCode) else { return nil }
            data = result.0
            URLCache.shared.storeCachedResponse(CachedURLResponse(response: result.1, data: data),
                                                for: request)
        }

        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
                kCGImageSourceShouldCacheImmediately: true,
              ] as CFDictionary) else { return nil }
        let image = UIImage(cgImage: cgImage)
        images.setObject(image, forKey: key,
                         cost: max(1, cgImage.bytesPerRow * cgImage.height))
        return image
    }
}

struct HarborArtworkImage: View {
    let url: String?
    var contentMode: ContentMode = .fill
    var maxPixelSize: CGFloat = 1600
    var fallbackText: String? = nil
    var showProgress = false

    @State private var image: UIImage?
    @State private var finished = false

    var body: some View {
        ZStack {
            Color.white.opacity(0.055)
            if let image {
                Image(uiImage: image).resizable().aspectRatio(contentMode: contentMode)
            } else if showProgress && !finished {
                ProgressView()
            } else if let fallbackText, finished {
                Text(fallbackText)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.58))
                    .multilineTextAlignment(.center)
                    .padding(8)
            }
        }
        .clipped()
        .task(id: url) {
            image = nil
            finished = false
            let loaded = await HarborArtworkCache.shared.image(for: url,
                                                                 maxPixelSize: maxPixelSize)
            guard !Task.isCancelled else { return }
            image = loaded
            finished = true
        }
    }
}
