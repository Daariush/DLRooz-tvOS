import SwiftUI
import UIKit

/// Loads site images through the site session (cookies + UA), with memory and URL caches.
final class ImageLoader: @unchecked Sendable {
    static let shared = ImageLoader()
    private let memory = NSCache<NSURL, UIImage>()
    private let session: URLSession
    private var inFlight: [URL: Task<UIImage?, Never>] = [:]
    private let lock = NSLock()
    var jar: CookieJar?

    private init() {
        memory.countLimit = 400
        let config = URLSessionConfiguration.default
        config.urlCache = URLCache(memoryCapacity: 30 << 20, diskCapacity: 300 << 20)
        config.requestCachePolicy = .returnCacheDataElseLoad
        config.httpShouldSetCookies = false
        config.httpAdditionalHeaders = ["User-Agent": SiteConfig.userAgent]
        session = URLSession(configuration: config)
    }

    func cached(_ url: URL) -> UIImage? { memory.object(forKey: url as NSURL) }

    func load(_ url: URL) async -> UIImage? {
        if let img = cached(url) { return img }
        lock.lock()
        if let t = inFlight[url] {
            lock.unlock()
            return await t.value
        }
        let task = Task<UIImage?, Never> { [session, jar] in
            var req = URLRequest(url: url)
            if let cookie = jar?.header(for: url) { req.setValue(cookie, forHTTPHeaderField: "Cookie") }
            guard let result = try? await session.data(for: req), let img = UIImage(data: result.0) else { return nil }
            return img.preparingForDisplay() ?? img
        }
        inFlight[url] = task
        lock.unlock()
        let img = await task.value
        lock.lock(); inFlight[url] = nil; lock.unlock()
        if let img { memory.setObject(img, forKey: url as NSURL) }
        return img
    }

    func clear() {
        memory.removeAllObjects()
        session.configuration.urlCache?.removeAllCachedResponses()
    }
}

/// An image from the site, faded in; shows `placeholder` until loaded.
struct RemoteImage: View {
    let url: URL?
    var contentMode: ContentMode = .fill
    @State private var image: UIImage?

    var body: some View {
        ZStack {
            if let image {
                Image(uiImage: image).resizable().aspectRatio(contentMode: contentMode)
                    .transition(.opacity)
            } else {
                Rectangle().fill(Color.white.opacity(0.06))
            }
        }
        .task(id: url) {
            guard let url else { image = nil; return }
            if let hit = ImageLoader.shared.cached(url) { image = hit; return }
            let img = await ImageLoader.shared.load(url)
            withAnimation(.easeOut(duration: 0.25)) { image = img }
        }
    }
}
