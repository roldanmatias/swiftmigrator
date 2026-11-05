import Foundation

/// Downloads thumbnails concurrently, with a limit on in-flight tasks.
public final class ImagePrefetcher: Sendable {
    public typealias Loader = @Sendable (URL) async -> Data?

    private let loader: Loader
    private let maxConcurrentTasks: Int

    public init(maxConcurrentTasks: Int = 6, loader: @escaping Loader) {
        self.maxConcurrentTasks = max(1, maxConcurrentTasks)
        self.loader = loader
    }

    public func prefetch(_ urls: [URL]) async -> [URL: Data] {
        let loader = self.loader   // capture the Sendable closure, not `self`
        return await withTaskGroup(of: (URL, Data?).self) { group in
            var pending = urls.makeIterator()

            for _ in 0..<maxConcurrentTasks {
                guard let url = pending.next() else { break }
                group.addTask { (url, await loader(url)) }
            }

            var results: [URL: Data] = [:]
            for await (url, data) in group {
                if let data { results[url] = data }
                // One task finished, so start the next one.
                if let next = pending.next() {
                    group.addTask { (next, await loader(next)) }
                }
            }
            return results
        }
    }
}
