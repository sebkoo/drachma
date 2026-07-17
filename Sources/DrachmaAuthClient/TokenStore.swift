import Foundation

/// Where tokens live between launches. The app provides the Keychain-backed
/// conformance (`KeychainTokenStore` in DrachmaApp — the Security framework
/// is an Apple-platform dependency this target refuses to take on); tests
/// use the in-memory one.
public protocol TokenStore: Sendable {
    func load() throws -> OAuthTokens?
    func save(_ tokens: OAuthTokens) throws
    func clear() throws
}

public final class InMemoryTokenStore: TokenStore, @unchecked Sendable {
    private let lock = NSLock()
    private var tokens: OAuthTokens?

    public init(tokens: OAuthTokens? = nil) {
        self.tokens = tokens
    }

    public func load() throws -> OAuthTokens? {
        lock.lock(); defer { lock.unlock() }
        return tokens
    }

    public func save(_ tokens: OAuthTokens) throws {
        lock.lock(); defer { lock.unlock() }
        self.tokens = tokens
    }

    public func clear() throws {
        lock.lock(); defer { lock.unlock() }
        tokens = nil
    }
}
