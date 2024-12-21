//
//  CachedAsyncImage.swift
//  WatchClips Watch App
//
//  Created by Zakariya Hassan on 17/12/2024.
//

import SwiftUI
import CryptoKit

fileprivate struct ImageCache {
    static let inMemoryCache = NSCache<NSURL, UIImage>()
}

struct CachedAsyncImage<Content: View>: View {
    private let url: URL
    private let content: (Image) -> Content

    @State private var uiImage: UIImage?
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
            } else {
                Rectangle()
                    .fill(Color.gray.opacity(0.3))
                    .frame(height: 150)
                    .onAppear {
                        loadInitialImage()
                    }
            }
        }
    }

    /// Loads the initial image from cache sources (memory, disk, URLCache).
    /// If found, display it immediately and then do a background fetch to refresh it.
    /// If not found, attempt a direct network fetch.
    private func loadInitialImage() {
        // 1. Check In-Memory Cache
        if let cachedImage = ImageCache.inMemoryCache.object(forKey: url as NSURL) {
            self.uiImage = cachedImage
            backgroundRefresh() // Refresh in the background
            return
        }

        // 2. Check Disk Storage
        if let diskImage = loadFromDisk() {
            ImageCache.inMemoryCache.setObject(diskImage, forKey: url as NSURL)
            self.uiImage = diskImage
            backgroundRefresh() // Refresh in the background
            return
        }

        // 3. Check URLCache
        let request = URLRequest(url: url)
        if let cachedResponse = URLCache.shared.cachedResponse(for: request),
           let image = UIImage(data: cachedResponse.data) {
            ImageCache.inMemoryCache.setObject(image, forKey: url as NSURL)
            self.uiImage = image
            backgroundRefresh() // Refresh in the background
            return
        }

        // 4. No cached image found, fetch from network directly
        fetchImageFromNetwork(updateUI: true) { success in
            if success {
                // If fetched successfully, we have the latest image now.
            } else {
                // If failed, handle retries or just show placeholder
                DispatchQueue.main.async {
                    self.attempts += 1
                    if self.attempts <= self.maxRetries {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                            self.loadInitialImage()
                        }
                    }
                }
            }
        }
    }

    /// Performs a background refresh to always keep the image up-to-date.
    /// This will fetch from the network and if a newer image is available,
    /// update the cache and UI.
    private func backgroundRefresh() {
        fetchImageFromNetwork(updateUI: false) { success in
            // If success and different image is fetched, UI will update automatically
            // If same image is fetched, no update needed
        }
    }

    /// Fetches the image from the network. If `updateUI` is true, it will
    /// update the displayed image immediately. If false, it will only update
    /// the UI if the newly fetched image differs from the currently displayed one.
    private func fetchImageFromNetwork(updateUI: Bool, completion: @escaping (Bool) -> Void) {
        let request = URLRequest(url: url)
        URLSession.shared.dataTask(with: request) { data, response, _ in
            guard let data = data, let response = response, let newImage = UIImage(data: data) else {
                completion(false)
                return
            }

            DispatchQueue.main.async {
                // Check if we already have an image displayed
                let currentData = self.uiImage?.pngData() ?? Data()
                let newData = data

                // Cache in URLCache
                let cachedData = CachedURLResponse(response: response, data: data)
                URLCache.shared.storeCachedResponse(cachedData, for: request)

                // Cache in in-memory NSCache
                ImageCache.inMemoryCache.setObject(newImage, forKey: self.url as NSURL)

                // Save to disk for persistence
                self.saveToDisk(image: newImage)

                if updateUI {
                    // Always update UI if we requested it
                    self.uiImage = newImage
                    completion(true)
                } else {
                    // Update UI only if the new image is different
                    if newData != currentData {
                        self.uiImage = newImage
                    }
                    completion(true)
                }
            }
        }.resume()
    }

    // MARK: - Disk Storage

    private func loadFromDisk() -> UIImage? {
        let fileURL = imageFileURL(for: url)
        guard FileManager.default.fileExists(atPath: fileURL.path),
              let data = try? Data(contentsOf: fileURL),
              let image = UIImage(data: data) else {
            return nil
        }
        return image
    }

    private func saveToDisk(image: UIImage) {
        let fileURL = imageFileURL(for: url)
        // Convert image to data (JPEG or PNG)
        if let data = image.jpegData(compressionQuality: 0.9) ?? image.pngData() {
            try? data.write(to: fileURL, options: [.atomic])
        }
    }

    private func imageFileURL(for url: URL) -> URL {
        // Create a filename unique to this URL by hashing it
        let hashedName = sha256(url.absoluteString) + ".imgcache"
        let cachesURL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        return cachesURL.appendingPathComponent(hashedName)
    }

    private func sha256(_ string: String) -> String {
        let inputData = Data(string.utf8)
        let hashed = SHA256.hash(data: inputData)
        return hashed.map { String(format: "%02x", $0) }.joined()
    }
}
