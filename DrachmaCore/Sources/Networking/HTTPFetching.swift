import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// The one seam between DrachmaCore and the network — injected so tests can
/// stub responses without touching URLSession.
public protocol HTTPFetching: Sendable {
    func fetch(_ request: URLRequest) async throws -> (data: Data, statusCode: Int)
}

extension URLSession: HTTPFetching {
    public func fetch(_ request: URLRequest) async throws -> (data: Data, statusCode: Int) {
        let (data, response) = try await data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? -1
        return (data, status)
    }
}
