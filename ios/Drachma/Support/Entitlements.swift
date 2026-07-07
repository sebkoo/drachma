/// The free/Pro seam, designed before any paywall exists. The App Store build
/// will eventually back this with StoreKit; the open-source build can provide
/// its own conformance — you can always build Pro yourself, and buying the
/// App Store version supports development. Both are legitimate; that's the deal.
public protocol EntitlementProviding: Sendable {
    var maxFavoritePairs: Int { get }
}

/// The pledge in code: the core converter stays free forever, and the free
/// tier is genuinely useful. Pro will only ever lift ongoing-value limits.
public struct FreeTier: EntitlementProviding {
    public let maxFavoritePairs = 5

    public init() {}
}
