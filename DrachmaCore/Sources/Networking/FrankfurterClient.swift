import Foundation

public enum RatesClientError: Error, Equatable, Sendable {
    case badStatus(Int)
    case malformedURL
}

/// Anything that can answer "what are the reference rates?" — the app, its
/// widgets, and drachma-mcp all depend on this protocol, never on Frankfurter
/// directly.
public protocol RatesClient: Sendable {
    /// The most recent ECB reference rates.
    func latestRates(base: String) async throws -> RatesSnapshot

    /// The reference rates for a specific ECB working day (`yyyy-MM-dd`).
    func rates(on day: String, base: String) async throws -> RatesSnapshot
}

/// Live client for the keyless Frankfurter API (ECB reference rates).
public struct FrankfurterClient: RatesClient {
    private let baseURL: URL
    private let http: any HTTPFetching

    public init(
        http: any HTTPFetching = URLSession.shared,
        baseURL: URL = URL(string: "https://api.frankfurter.dev/v1")!
    ) {
        self.http = http
        self.baseURL = baseURL
    }

    public func latestRates(base: String) async throws -> RatesSnapshot {
        try await snapshot(path: "latest", base: base)
    }

    public func rates(on day: String, base: String) async throws -> RatesSnapshot {
        try await snapshot(path: day, base: base)
    }

    private func snapshot(path: String, base: String) async throws -> RatesSnapshot {
        var components = URLComponents(
            url: baseURL.appending(path: path),
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = [URLQueryItem(name: "base", value: base)]
        guard let url = components?.url else { throw RatesClientError.malformedURL }

        let (data, status) = try await http.fetch(URLRequest(url: url))
        guard status == 200 else { throw RatesClientError.badStatus(status) }
        return try JSONDecoder().decode(RatesSnapshot.self, from: data)
    }
}
