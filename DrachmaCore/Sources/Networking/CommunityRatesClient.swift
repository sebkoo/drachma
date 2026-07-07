import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Community-sourced daily rates via currency-api (fawazahmed0/exchange-api):
/// 200+ currencies, keyless, CDN-served, refreshed daily. Everything it
/// returns is tagged `.community` so surfaces can label it honestly —
/// indicative coverage where the ECB doesn't reach (VND, COP, PEN, …).
public struct CommunityRatesClient: RatesClient {
    private let http: any HTTPFetching
    /// Version tag ("latest" or yyyy-MM-dd) is interpolated after the `@`.
    private let root: String

    public init(
        http: any HTTPFetching = URLSession.shared,
        root: String = "https://cdn.jsdelivr.net/npm/@fawazahmed0/currency-api"
    ) {
        self.http = http
        self.root = root
    }

    public func latestRates(base: String) async throws -> RatesSnapshot {
        try await snapshot(version: "latest", base: base)
    }

    public func rates(on day: String, base: String) async throws -> RatesSnapshot {
        try await snapshot(version: day, base: base)
    }

    /// All currency codes the community source serves.
    public func currencyCodes() async throws -> [String] {
        guard let url = URL(string: "\(root)@latest/v1/currencies.json") else {
            throw RatesClientError.malformedURL
        }
        let (data, status) = try await http.fetch(URLRequest(url: url))
        guard status == 200 else { throw RatesClientError.badStatus(status) }
        let names = try JSONDecoder().decode([String: String].self, from: data)
        return names.keys.map { $0.uppercased() }.sorted()
    }

    private func snapshot(version: String, base: String) async throws -> RatesSnapshot {
        let code = base.lowercased()
        guard let url = URL(string: "\(root)@\(version)/v1/currencies/\(code).json") else {
            throw RatesClientError.malformedURL
        }
        let (data, status) = try await http.fetch(URLRequest(url: url))
        guard status == 200 else { throw RatesClientError.badStatus(status) }
        let payload = try JSONDecoder().decode(CommunityPayload.self, from: data)
        return RatesSnapshot(
            base: base.uppercased(),
            date: payload.date,
            rates: payload.rates,
            source: .community
        )
    }
}

/// currency-api keys the rates object by the base code itself
/// ({"date": "...", "usd": {"eur": 0.87, ...}}), so decoding is dynamic.
private struct CommunityPayload: Decodable {
    let date: String
    let rates: [String: Decimal]

    private struct DynamicKey: CodingKey {
        var stringValue: String
        var intValue: Int? { nil }
        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { nil }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: DynamicKey.self)
        var date = ""
        var rates: [String: Decimal] = [:]
        for key in container.allKeys {
            if key.stringValue == "date" {
                date = try container.decode(String.self, forKey: key)
            } else {
                let raw = try container.decode([String: Double].self, forKey: key)
                for (code, value) in raw {
                    rates[code.uppercased()] = Decimal(value)
                }
            }
        }
        self.date = date
        self.rates = rates
    }
}
