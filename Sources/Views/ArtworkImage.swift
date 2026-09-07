import ImageIO
import SwiftUI
import UIKit

/// Shared decoded-artwork cache. SwiftUI's `AsyncImage` creates a fresh decode
/// for cards as rows leave/re-enter the viewport; keeping downsampled UIImages
/// avoids those focus-scroll hitches and lowers peak memory on older Apple TVs.
actor HarborArtworkCache {
    static let shared = HarborArtworkCache()
    private let images = NSCache<NSString, UIImage>()
    private struct PendingImage {
        let id: UUID
        let cacheGeneration: UInt
        let task: Task<Void, Never>
        var consumers: [UUID: CheckedContinuation<UIImage?, Never>]
    }
    private struct LoadSlot {
        let id: UUID
        let continuation: CheckedContinuation<Bool, Never>
    }
    private var inFlight: [String: PendingImage] = [:]
    private var activeLoads = 0
    private var slots: [LoadSlot] = []
    private var cacheGeneration: UInt = 0

    init() {
        images.countLimit = 120
        images.totalCostLimit = 64 * 1024 * 1024
    }

    func image(for rawURL: String?, maxPixelSize: CGFloat = 1600) async -> UIImage? {
        guard !Task.isCancelled, let rawURL, !rawURL.isEmpty,
              let url = URL(string: rawURL), maxPixelSize.isFinite else { return nil }
        let pixelSize = min(3840, max(64, maxPixelSize.rounded(.up)))
        let key = "\(rawURL)|\(Int(pixelSize))"
        if let cached = images.object(forKey: key as NSString) { return cached }
        let consumer = UUID()
        // A disappearing card must release its request immediately. Another visible
        // card sharing this image keeps the download alive; the last one cancels it.
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                guard !Task.isCancelled else { continuation.resume(returning: nil); return }
                if inFlight[key] != nil {
                    inFlight[key]?.consumers[consumer] = continuation
                } else {
                    let id = UUID()
                    let task = Task {
                        let image = await self.load(url: url, maxPixelSize: pixelSize)
                        self.finish(key: key, id: id, image: image)
                    }
                    inFlight[key] = PendingImage(id: id, cacheGeneration: cacheGeneration,
                        task: task, consumers: [consumer: continuation])
                }
            }
        } onCancel: {
            Task { await self.cancelConsumer(consumer, key: key) }
        }
    }

    func purge() {
        images.removeAllObjects()
        // Do not refill a freshly purged cache with downloads already in progress.
        cacheGeneration &+= 1
    }

    private func cancelConsumer(_ consumer: UUID, key: String) {
        guard let continuation = inFlight[key]?.consumers.removeValue(forKey: consumer) else { return }
        continuation.resume(returning: nil)
        if inFlight[key]?.consumers.isEmpty == true {
            let load = inFlight.removeValue(forKey: key)
            load?.task.cancel()
        }
    }

    private func finish(key: String, id: UUID, image: UIImage?) {
        // A canceled load may finish after a new request for the same URL starts.
        guard let pending = inFlight[key], pending.id == id else { return }
        inFlight[key] = nil
        if pending.cacheGeneration == cacheGeneration,
           let image, let cgImage = image.cgImage {
            images.setObject(image, forKey: key as NSString,
                             cost: cgImage.bytesPerRow * cgImage.height)
        }
        for consumer in pending.consumers.values { consumer.resume(returning: image) }
    }

    private func acquireSlot() async -> Bool {
        guard !Task.isCancelled else { return false }
        if activeLoads < 4 { activeLoads += 1; return true }
        let id = UUID()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                guard !Task.isCancelled else { continuation.resume(returning: false); return }
                slots.append(LoadSlot(id: id, continuation: continuation))
            }
        } onCancel: {
            Task { await self.cancelSlot(id) }
        }
    }

    private func cancelSlot(_ id: UUID) {
        guard let index = slots.firstIndex(where: { $0.id == id }) else { return }
        slots.remove(at: index).continuation.resume(returning: false)
    }

    private func releaseSlot() {
        if slots.isEmpty { activeLoads -= 1 }
        else { slots.removeFirst().continuation.resume(returning: true) }
    }

    private func load(url: URL, maxPixelSize: CGFloat) async -> UIImage? {
        // Avoid a burst of dozens of image decodes competing with VideoToolbox.
        guard await acquireSlot() else { return nil }
        defer { releaseSlot() }
        guard !Task.isCancelled else { return nil }

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

        guard !Task.isCancelled else { return nil }
        // ImageIO work stays off this actor, so a large hero decode cannot delay
        // cache hits, cancellation or new visible-card requests behind it.
        let decode = Task.detached(priority: .userInitiated) {
            Self.decode(data: data, maxPixelSize: maxPixelSize)
        }
        return await withTaskCancellationHandler {
            let image = await decode.value
            return Task.isCancelled ? nil : image
        } onCancel: { decode.cancel() }
    }

    private nonisolated static func decode(data: Data, maxPixelSize: CGFloat) -> UIImage? {
        guard !Task.isCancelled,
              let source = CGImageSourceCreateWithData(data as CFData,
                [kCGImageSourceShouldCache: false] as CFDictionary),
              let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
                kCGImageSourceShouldCacheImmediately: true,
              ] as CFDictionary) else { return nil }
        return Task.isCancelled ? nil : UIImage(cgImage: cgImage)
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
    @State private var loadedKey: String?

    private var requestKey: String { "\(url ?? "")|\(maxPixelSize)" }

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
        .task(id: requestKey) {
            guard loadedKey != requestKey else { return }
            loadedKey = nil
            image = nil
            finished = false
            let loaded = await HarborArtworkCache.shared.image(for: url,
                                                                 maxPixelSize: maxPixelSize)
            guard !Task.isCancelled else { return }
            image = loaded
            if loaded != nil { loadedKey = requestKey }
            finished = true
        }
    }
}
