import Foundation

/// Public types must declare `Sendable` explicitly; it's part of the API contract.
public struct Article: Equatable, Codable, Sendable {
    public let id: Int
    public let title: String
    public var isRead: Bool

    public init(id: Int, title: String, isRead: Bool = false) {
        self.id = id
        self.title = title
        self.isRead = isRead
    }
}

public enum FeedError: Error, Equatable, Sendable {
    case network
    case decoding
}
