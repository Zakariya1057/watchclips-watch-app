//
//  CachedAsyncImage.swift
//  WatchClips Watch App
//
//  Created by Zakariya Hassan on 17/12/2024.
//

import SwiftUI
import CryptoKit

fileprivate actor ImageMemoryCache {
    static let shared = ImageMemoryCache()

    private var cache = NSCache<NSURL, UIImage>()

    func image(for url: URL) -> UIImage? {
        cache.object(forKey: url as NSURL)
    }

    func setImage(_ image: UIImage, for url: URL) {
        cache.setObject(image, forKey: url as NSURL)
    }
}

struct CachedAsyncImage<Content: View>: View {
    private let url: URL
    private let content: (Image) -> Content

    @State private var uiImage: UIImage?
    @State private var isLoading = false
    @State private var attempts = 0
    private let maxRetries = 3

    init(url: URL, @ViewBuilder content: @escaping (Image) -> Content) {
        self.url = url
        self.content = content
    }

    var body: some View {
        Group {
            if let uiImage = uiImage {
                content(Image(uiImage: uiImage))
                    .frame(height: 150)
            } else {
                Rectangle()
                    .fill(Color.gray.opacity(0.3))
                    .frame(height: 150)
                    .onAppear {
                        Task {
                            await loadImageIfNeeded()
                        }
                    }
            }
        }
    }

    // MARK: - Image Loading

    private func loadImageIfNeeded() async {
        guard !isLoading else { return }
        isLoading = true

        // 1. In-Memory Cache
        if let cached = await ImageMemoryCache.shared.image(for: url) {
            uiImage = cached
            isLoading = false
            return
        }

        // 2. Disk Storage
        if let diskImage = await loadFromDisk() {
            await ImageMemoryCache.shared.setImage(diskImage, for: url)
            uiImage = diskImage
            isLoading = false
            return
        }

        // 3. URLCache
        if let image = await loadFromURLCache() {
            await ImageMemoryCache.shared.setImage(image, for: url)
            uiImage = image
            isLoading = false
            return
        }

        // 4. Network
        let success = await fetchImageFromNetwork()
        if !success, attempts < maxRetries {
            attempts += 1
            // Optional short delay to avoid spamming, but keep it small
            try? await Task.sleep(nanoseconds: 300_000_000)
            isLoading = false
            await loadImageIfNeeded()
        } else {
            isLoading = false
        }
    }

    @MainActor
    private func loadFromURLCache() async -> UIImage? {
        let request = URLRequest(url: url)
        if let cachedResponse = URLCache.shared.cachedResponse(for: request),
           let image = UIImage(data: cachedResponse.data) {
            return image
        }
        return nil
    }

    @MainActor
    private func fetchImageFromNetwork() async -> Bool {
        let request = URLRequest(url: url)

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                return false
            }

            guard let newImage = await decodeImageData(data) else {
                return false
            }

            // Cache in URLCache
            let cachedData = CachedURLResponse(response: httpResponse, data: data)
            URLCache.shared.storeCachedResponse(cachedData, for: request)

            // Cache in memory
            await ImageMemoryCache.shared.setImage(newImage, for: url)

            // Save to disk (off-main)
            Task.detached {
                await saveToDisk(image: newImage, url: url)
            }

            uiImage = newImage
            return true
        } catch {
            return false
        }
    }

    // MARK: - Disk Storage

    private func loadFromDisk() async -> UIImage? {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                let fileURL = imageFileURL(for: url)
                guard FileManager.default.fileExists(atPath: fileURL.path),
                      let data = try? Data(contentsOf: fileURL),
                      let image = UIImage(data: data)
                else {
                    continuation.resume(returning: nil)
                    return
                }
                continuation.resume(returning: image)
            }
        }
    }

    private func saveToDisk(image: UIImage, url: URL) async {
        let fileURL = imageFileURL(for: url)
        guard let data = image.jpegData(compressionQuality: 0.1)
                ?? image.pngData() else { return }

        do {
            try data.write(to: fileURL, options: [.atomic])
        } catch {
            // Handle disk write error if needed
        }
    }

    private func imageFileURL(for url: URL) -> URL {
        let hashedName = sha256(url.absoluteString) + ".imgcache"
        let cachesURL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        return cachesURL.appendingPathComponent(hashedName)
    }

    private func sha256(_ string: String) -> String {
        let inputData = Data(string.utf8)
        let hashed = SHA256.hash(data: inputData)
        return hashed.map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - Image Decoding

    private func decodeImageData(_ data: Data) async -> UIImage? {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                let decoded = UIImage(data: data)
                continuation.resume(returning: decoded)
            }
        }
    }
}
