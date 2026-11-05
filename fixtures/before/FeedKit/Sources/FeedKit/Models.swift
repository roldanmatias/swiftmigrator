import Foundation

/// Public value type: implicitly Sendable inside this module, but NOT for clients.
public struct Article: Equatable, Codable {
    public let id: Int
    public let title: String
    public var isRead: Bool

    public init(id: Int, title: String, isRead: Bool = false) {
        self.id = id
        self.title = title
        self.isRead = isRead
    }
}

public enum FeedError: Error, Equatable {
    case network
    case decoding
}
