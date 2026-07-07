import Foundation
import Observation

public struct FavoritePair: Codable, Hashable, Sendable {
    public let base: String
    public let quote: String

    public init(base: String, quote: String) {
        self.base = base.uppercased()
        self.quote = quote.uppercased()
    }
}

/// User's saved pairs — persisted, capped by the entitlement seam. Favorites
/// survive updates by design: losing a user's saved list on update is a
/// recurring 1-star pattern in competitor reviews.
@Observable @MainActor
public final class FavoritesStore {
    public private(set) var pairs: [FavoritePair] = []

    private let entitlements: any EntitlementProviding
    private let defaults: UserDefaults
    private static let key = "favoritePairs"

    public init(
        entitlements: any EntitlementProviding = FreeTier(),
        defaults: UserDefaults = .standard
    ) {
        self.entitlements = entitlements
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.key),
           let saved = try? JSONDecoder().decode([FavoritePair].self, from: data) {
            pairs = saved
        }
    }

    public var isAtLimit: Bool {
        pairs.count >= entitlements.maxFavoritePairs
    }

    /// Returns false when the pair is a duplicate or the tier limit is reached.
    @discardableResult
    public func add(_ pair: FavoritePair) -> Bool {
        guard !pairs.contains(pair), !isAtLimit else { return false }
        pairs.append(pair)
        persist()
        return true
    }

    public func remove(_ pair: FavoritePair) {
        pairs.removeAll { $0 == pair }
        persist()
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(pairs) {
            defaults.set(data, forKey: Self.key)
        }
    }
}
