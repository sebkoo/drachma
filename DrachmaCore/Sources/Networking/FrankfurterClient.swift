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

    /// The currencies the ECB publishes reference rates for, per the live
    /// Frankfurter /v1/currencies endpoint (verified 2026-07-07). The list has
    /// been stable for years; composite routing keys off it.
    public static let supportedCurrencyCodes: Set<String> = [
        "AUD", "BRL", "CAD", "CHF", "CNY", "CZK", "DKK", "EUR", "GBP", "HKD",
        "HUF", "IDR", "ILS", "INR", "ISK", "JPY", "KRW", "MXN", "MYR", "NOK",
        "NZD", "PHP", "PLN", "RON", "SEK", "SGD", "THB", "TRY", "USD", "ZAR",
    ]

    public func latestRates(base: String) async throws -> RatesSnapshot {
        try await snapshot(path: "latest", base: base)
    }

    public func rates(on day: String, base: String) async throws -> RatesSnapshot {
        try await snapshot(path: day, base: base)
    }

    private func snapshot(path: String, base: String) async throws -> RatesSnapshot {
        let decoded: RatesSnapshot = try await get(path: path, query: [URLQueryItem(name: "base", value: base)])
        return RatesSnapshot(base: decoded.base, date: decoded.date, rates: decoded.rates, source: .ecb)
    }

    private func get<Response: Decodable>(path: String, query: [URLQueryItem]) async throws -> Response {
        var components = URLComponents(
            url: baseURL.appending(path: path),
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = query
        guard let url = components?.url else { throw RatesClientError.malformedURL }

        let (data, status) = try await http.fetch(URLRequest(url: url))
        guard status == 200 else { throw RatesClientError.badStatus(status) }
        return try JSONDecoder().decode(Response.self, from: data)
    }
}

extension FrankfurterClient: RatesSeriesClient {
    public func series(from: String, to: String, base: String, quote: String) async throws -> RatesSeries {
        try await get(path: "\(from)..\(to)", query: [
            URLQueryItem(name: "base", value: base),
            URLQueryItem(name: "symbols", value: quote),
        ])
    }
}
