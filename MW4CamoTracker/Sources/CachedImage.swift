import CryptoKit
import SwiftUI
import UIKit

/// Pictures kept on the phone for good: weapon art, camo swatches, DMZ item
/// and trait icons. Every picture URL in the data is versioned (a new file
/// name or a `?v=` bump when the art changes), so a stored copy never goes
/// stale and is never re-fetched. Only successful downloads are kept: a
/// missing file is tried again next time, so a picture published after the
/// data can't stay blank for hours the way GitHub Pages' cached 404s did.
final class ImageStore: @unchecked Sendable {
    static let shared = ImageStore()

    private let memory = NSCache<NSURL, UIImage>()
    private let folder: URL
    private let lock = NSLock()
    /// One download per URL at a time, however many views ask for it
    private var inFlight: [URL: Task<UIImage?, Never>] = [:]

    private init() {
        memory.countLimit = 400
        folder = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("images", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    private func file(for url: URL) -> URL {
        let hash = SHA256.hash(data: Data(url.absoluteString.utf8)).map { String(format: "%02x", $0) }.joined()
        return folder.appendingPathComponent(hash)
    }

    /// Already in memory: drawn straight away, with no placeholder flash.
    func cached(_ url: URL) -> UIImage? {
        memory.object(forKey: url as NSURL)
    }

    /// The shared download for this URL, started if none is running.
    private func download(_ url: URL, to path: URL) -> Task<UIImage?, Never> {
        lock.withLock {
            if let task = inFlight[url] { return task }
            let task = Task<UIImage?, Never> { [memory] in
                var request = URLRequest(url: url)
                // The disk copy is the cache; skip URLCache's stored answers,
                // which include GitHub Pages' four-hour 404s
                request.cachePolicy = .reloadIgnoringLocalCacheData
                guard let (data, response) = try? await URLSession.shared.data(for: request),
                      (response as? HTTPURLResponse)?.statusCode == 200,
                      let image = UIImage(data: data) else { return nil }
                try? data.write(to: path, options: .atomic)
                memory.setObject(image, forKey: url as NSURL)
                return image
            }
            inFlight[url] = task
            return task
        }
    }

    /// Memory, then disk, then the network.
    func image(for url: URL) async -> UIImage? {
        if let image = cached(url) { return image }
        let path = file(for: url)
        if let data = try? Data(contentsOf: path), let image = UIImage(data: data) {
            memory.setObject(image, forKey: url as NSURL)
            return image
        }
        let task = download(url, to: path)
        let image = await task.value
        lock.withLock { inFlight[url] = nil }
        return image
    }
}

/// `AsyncImage` with the phone-side cache: same phases, so it drops in
/// wherever `AsyncImage(url:) { phase in ... }` was used.
struct CachedAsyncImage<Content: View>: View {
    let url: URL?
    @ViewBuilder let content: (AsyncImagePhase) -> Content
    @State private var loaded: UIImage?
    @State private var failed = false

    init(url: URL?, @ViewBuilder content: @escaping (AsyncImagePhase) -> Content) {
        self.url = url
        self.content = content
        _loaded = State(initialValue: url.flatMap { ImageStore.shared.cached($0) })
    }

    private var phase: AsyncImagePhase {
        if let loaded { return .success(Image(uiImage: loaded)) }
        if failed { return .failure(URLError(.badServerResponse)) }
        return .empty
    }

    var body: some View {
        content(phase)
            .task(id: url) {
                guard let url else { failed = true; return }
                if let image = ImageStore.shared.cached(url) { loaded = image; return }
                loaded = nil
                failed = false
                if let image = await ImageStore.shared.image(for: url) { loaded = image } else { failed = true }
            }
    }
}
