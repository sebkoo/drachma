import Foundation
@testable import DrachmaCore

/// Records request URLs across concurrency boundaries for assertions.
final class RequestBox: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: [URL] = []

    func append(_ url: URL?) {
        lock.lock()
        defer { lock.unlock() }
        if let url { stored.append(url) }
    }

    var urls: [URL] {
        lock.lock()
        defer { lock.unlock() }
        return stored
    }
}

struct StubHTTP: HTTPFetching {
    let data: Data
    let statusCode: Int
    let box: RequestBox

    func fetch(_ request: URLRequest) async throws -> (data: Data, statusCode: Int) {
        box.append(request.url)
        return (data, statusCode)
    }
}
