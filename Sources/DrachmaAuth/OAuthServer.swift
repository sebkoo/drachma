import Foundation

public enum OAuthError: Error, Equatable, Sendable {
    case unknownClient
    case invalidRedirectURI
    case unsupportedChallengeMethod
    case invalidScope
    case invalidGrant        // unknown / reused / expired authorization code
    case pkceVerificationFailed
}

/// A registered OAuth client (RFC 6749 §2). Public clients (no secret) rely on
/// PKCE, which is exactly the MCP-agent case.
public struct OAuthClient: Sendable, Equatable {
    public let id: String
    public let redirectURIs: Set<String>
    public let allowedScopes: Set<String>

    public init(id: String, redirectURIs: Set<String>, allowedScopes: Set<String>) {
        self.id = id
        self.redirectURIs = redirectURIs
        self.allowedScopes = allowedScopes
    }
}

/// An issued access token (opaque bearer). Audience-bound per the MCP auth
/// spec so it can't be replayed against a different resource server.
public struct AccessToken: Sendable, Equatable {
    public let value: String
    public let clientID: String
    public let scopes: Set<String>
    public let audience: String
    public let expiresAt: Date
}

/// A minimal OAuth 2.1 authorization server: authorization-code grant with
/// mandatory PKCE (S256), one-time codes, audience-bound access tokens, and
/// synchronous token introspection so it can back a resource server's bearer
/// validator directly.
///
/// Lock-guarded (not an actor) on purpose: the SDK's `BearerTokenValidator`
/// takes a *synchronous* token-validator closure, so introspection must be
/// callable without `await`.
public final class OAuthServer: @unchecked Sendable {
    private struct PendingCode {
        let clientID: String
        let redirectURI: String
        let codeChallenge: String
        let scopes: Set<String>
        let expiresAt: Date
        var redeemed: Bool
    }

    public let audience: String
    private let codeTTL: TimeInterval
    private let tokenTTL: TimeInterval
    private let now: @Sendable () -> Date

    private let lock = NSLock()
    private var clients: [String: OAuthClient] = [:]
    private var codes: [String: PendingCode] = [:]
    private var tokens: [String: AccessToken] = [:]

    public init(
        audience: String,
        codeTTL: TimeInterval = 60,
        tokenTTL: TimeInterval = 3600,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.audience = audience
        self.codeTTL = codeTTL
        self.tokenTTL = tokenTTL
        self.now = now
    }

    public func register(_ client: OAuthClient) {
        lock.lock(); defer { lock.unlock() }
        clients[client.id] = client
    }

    /// Authorization endpoint (RFC 6749 §4.1.1 + RFC 7636). Validates the
    /// client, redirect URI, S256 method, and requested scopes, then issues a
    /// short-lived one-time code bound to the PKCE challenge.
    public func authorize(
        clientID: String,
        redirectURI: String,
        codeChallenge: String,
        codeChallengeMethod: String,
        scope: Set<String>
    ) throws -> String {
        lock.lock(); defer { lock.unlock() }

        guard let client = clients[clientID] else { throw OAuthError.unknownClient }
        guard client.redirectURIs.contains(redirectURI) else { throw OAuthError.invalidRedirectURI }
        guard codeChallengeMethod == PKCE.method else { throw OAuthError.unsupportedChallengeMethod }
        guard scope.isSubset(of: client.allowedScopes) else { throw OAuthError.invalidScope }

        let code = Self.randomToken()
        codes[code] = PendingCode(
            clientID: clientID,
            redirectURI: redirectURI,
            codeChallenge: codeChallenge,
            scopes: scope,
            expiresAt: now().addingTimeInterval(codeTTL),
            redeemed: false
        )
        return code
    }

    /// Token endpoint (RFC 6749 §4.1.3). Exchanges a code + PKCE verifier for
    /// an access token. Codes are single-use and time-boxed; a failed or
    /// reused exchange is rejected as `invalidGrant`.
    public func token(
        code: String,
        codeVerifier: String,
        clientID: String,
        redirectURI: String
    ) throws -> AccessToken {
        lock.lock(); defer { lock.unlock() }

        guard var pending = codes[code] else { throw OAuthError.invalidGrant }
        guard !pending.redeemed, pending.expiresAt > now() else {
            codes[code] = nil
            throw OAuthError.invalidGrant
        }
        guard pending.clientID == clientID, pending.redirectURI == redirectURI else {
            throw OAuthError.invalidGrant
        }
        guard PKCE.verify(verifier: codeVerifier, matches: pending.codeChallenge) else {
            throw OAuthError.pkceVerificationFailed
        }

        pending.redeemed = true
        codes[code] = nil // one-time use

        let token = AccessToken(
            value: Self.randomToken(),
            clientID: clientID,
            scopes: pending.scopes,
            audience: audience,
            expiresAt: now().addingTimeInterval(tokenTTL)
        )
        tokens[token.value] = token
        return token
    }

    /// Synchronous introspection for the resource server: returns the token if
    /// it exists and hasn't expired, else nil.
    public func introspect(_ tokenValue: String) -> AccessToken? {
        lock.lock(); defer { lock.unlock() }
        guard let token = tokens[tokenValue] else { return nil }
        guard token.expiresAt > now() else {
            tokens[tokenValue] = nil
            return nil
        }
        return token
    }

    private static func randomToken() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        var rng = SystemRandomNumberGenerator()
        for index in bytes.indices { bytes[index] = rng.next() }
        return PKCE.base64URLEncode(Data(bytes))
    }
}
