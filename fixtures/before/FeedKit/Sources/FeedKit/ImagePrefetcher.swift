import Foundation

/// Downloads thumbnails concurrently.
public final class ImagePrefetcher {
    public typealias Loader = (URL) async -> Data?

    private let loader: Loader

    public init(loader: @escaping Loader) {
        self.loader = loader
    }

    /// Adds one child task per URL, all at once.
    public func prefetch(_ urls: [URL]) async -> [URL: Data] {
        await withTaskGroup(of: (URL, Data?).self) { group in
            for url in urls {
                group.addTask { (url, await self.loader(url)) }
            }
            var results: [URL: Data] = [:]
            for await (url, data) in group {
                if let data { results[url] = data }
            }
            return results
        }
    }
}
