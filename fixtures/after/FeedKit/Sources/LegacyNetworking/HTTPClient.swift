import Foundation

/// Public struct with only Sendable members, but NOT marked `Sendable`.
public struct HTTPResponse {
    public let statusCode: Int
    public let body: Data

    public init(statusCode: Int, body: Data) {
        self.statusCode = statusCode
        self.body = body
    }
}

/// Legacy callback-based client. The completion runs on a background queue,
/// but the closure is NOT annotated `@Sendable`.
public final class HTTPClient {
    public static let shared = HTTPClient()

    private let stubbedBody: Data

    public init(stubbedBody: Data = Data(HTTPClient.sampleJSON.utf8)) {
        self.stubbedBody = stubbedBody
    }

    public func get(_ url: URL, completion: @escaping (Result<HTTPResponse, Error>) -> Void) {
        DispatchQueue.global().async {
            completion(.success(HTTPResponse(statusCode: 200, body: self.stubbedBody)))
        }
    }

    public static let sampleJSON = """
    [
      {"id": 1, "title": "Swift 6 is here", "isRead": false},
      {"id": 2, "title": "Understanding Sendable", "isRead": false}
    ]
    """
}
