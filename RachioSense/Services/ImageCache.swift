import UIKit
import CryptoKit
import os

/// Persistent disk-based image cache with ETag change detection.
/// Images are stored in the app's Caches directory and survive app restarts.
/// ETags are persisted to detect server-side changes without re-downloading.
actor ImageCache {
    static let shared = ImageCache()

    private static let logger = Logger(subsystem: "com.rachiosense", category: "ImageCache")

    private let cacheDir: URL
    private let etagFile: URL
    private var etags: [String: String] = [:]  // url → etag
    private var memoryCache: [String: UIImage] = [:]

    private init() {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        cacheDir = caches.appendingPathComponent("ZoneImages", isDirectory: true)
        etagFile = caches.appendingPathComponent("zone_image_etags.json")

        try? FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
        // Load etags synchronously during init (before actor isolation kicks in)
        if let data = try? Data(contentsOf: etagFile),
           let dict = try? JSONDecoder().decode([String: String].self, from: data) {
            etags = dict
        }
    }

    // MARK: - Public API

    /// Fetch image for a URL. Returns cached version if available and unchanged.
    /// Uses ETag to detect server-side changes without downloading unnecessarily.
    func image(for urlString: String) async -> UIImage? {
        guard let url = URL(string: urlString) else { return nil }

        // 1. Return memory cache immediately
        if let cached = memoryCache[urlString] {
            return cached
        }

        // 2. Check disk cache
        let cacheKey = cacheKeyFor(urlString)
        let diskURL = cacheDir.appendingPathComponent(cacheKey)

        if FileManager.default.fileExists(atPath: diskURL.path),
           let data = try? Data(contentsOf: diskURL),
           let image = UIImage(data: data) {

            // Validate with ETag — do a HEAD request to check if image changed
            let changed = await hasImageChanged(url: url, cachedEtag: etags[urlString])
            if !changed {
                Self.logger.debug("Cache hit (disk): \(cacheKey)")
                memoryCache[urlString] = image
                return image
            }
            Self.logger.info("Image changed on server, re-downloading: \(cacheKey)")
        }

        // 3. Download fresh image
        return await download(url: url, urlString: urlString, diskURL: diskURL)
    }

    /// Pre-warm the cache for a list of URLs
    func prefetch(urls: [String]) async {
        await withTaskGroup(of: Void.self) { group in
            for url in urls {
                group.addTask {
                    _ = await self.image(for: url)
                }
            }
        }
    }

    /// Clear memory cache (disk cache persists)
    func clearMemory() {
        memoryCache.removeAll()
        Self.logger.debug("Memory cache cleared")
    }

    /// Clear all cached images and ETags
    func clearAll() {
        memoryCache.removeAll()
        etags.removeAll()
        try? FileManager.default.removeItem(at: cacheDir)
        try? FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
        try? FileManager.default.removeItem(at: etagFile)
        Self.logger.info("All image caches cleared")
    }

    // MARK: - Private

    private func hasImageChanged(url: URL, cachedEtag: String?) async -> Bool {
        guard let etag = cachedEtag else { return true } // No etag → assume changed

        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"
        request.setValue(etag, forHTTPHeaderField: "If-None-Match")
        request.timeoutInterval = 5

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse {
                if http.statusCode == 304 {
                    return false // Not modified
                }
                // Update etag if changed
                if let newEtag = http.value(forHTTPHeaderField: "ETag") {
                    etags[url.absoluteString] = newEtag
                    saveEtags()
                }
            }
        } catch {
            // Network error — return cached version
            Self.logger.warning("HEAD request failed for \(url.lastPathComponent): \(error.localizedDescription)")
            return false
        }

        return true
    }

    private func download(url: URL, urlString: String, diskURL: URL) async -> UIImage? {
        do {
            var request = URLRequest(url: url)
            // Include etag if we have one (for conditional GET)
            if let etag = etags[urlString] {
                request.setValue(etag, forHTTPHeaderField: "If-None-Match")
            }

            let (data, response) = try await URLSession.shared.data(for: request)

            guard let http = response as? HTTPURLResponse else { return nil }

            // 304 Not Modified — should not happen here but handle gracefully
            if http.statusCode == 304,
               let existing = try? Data(contentsOf: diskURL),
               let image = UIImage(data: existing) {
                memoryCache[urlString] = image
                return image
            }

            guard http.statusCode == 200,
                  let image = UIImage(data: data) else {
                Self.logger.warning("Download failed for \(url.lastPathComponent): HTTP \(http.statusCode)")
                return nil
            }

            // Store ETag for future change detection
            if let etag = http.value(forHTTPHeaderField: "ETag") {
                etags[urlString] = etag
                saveEtags()
            }

            // Write to disk
            try data.write(to: diskURL)
            memoryCache[urlString] = image

            Self.logger.info("Downloaded and cached: \(url.lastPathComponent)")
            return image

        } catch {
            Self.logger.error("Download error for \(url.lastPathComponent): \(error.localizedDescription)")
            return nil
        }
    }

    private func cacheKeyFor(_ urlString: String) -> String {
        // Use SHA256 hash of URL as filename to avoid path issues
        let data = Data(urlString.utf8)
        let hash = SHA256.hash(data: data)
        return hash.compactMap { String(format: "%02x", $0) }.joined() + ".jpg"
    }

    private func saveEtags() {
        guard let data = try? JSONEncoder().encode(etags) else { return }
        try? data.write(to: etagFile)
    }
}
