import Foundation

public enum OAuthError: Error, Equatable, Sendable {
    case unknownClient
    case invalidRedirectURI
    case unsupportedChallengeMethod
    case invalidScope
    case invalidGrant        // unknown / reused / expired authorization code or refresh token
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

/// What the token endpoint hands back (RFC 6749 §5.1): a short-lived access
/// token plus the rotating refresh token issued alongside it.
public struct IssuedTokens: Sendable, Equatable {
    public let access: AccessToken
    public let refreshToken: String
    public let refreshExpiresAt: Date
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

    /// A live refresh token. `rotated` flips on use; presenting a rotated
    /// token again is the theft signal that revokes the whole `familyID`.
    private struct RefreshRecord {
        let clientID: String
        let scopes: Set<String>
        let familyID: String
        let expiresAt: Date
        var rotated: Bool
    }

    public let audience: String
    private let codeTTL: TimeInterval
    private let tokenTTL: TimeInterval
    private let refreshTTL: TimeInterval
    private let now: @Sendable () -> Date

    private let lock = NSLock()
    private var clients: [String: OAuthClient] = [:]
    private var codes: [String: PendingCode] = [:]
    private var tokens: [String: AccessToken] = [:]
    private var refreshTokens: [String: RefreshRecord] = [:]
    /// Access-token value → family, so reuse detection can revoke bearers too.
    private var accessFamily: [String: String] = [:]

    public init(
        audience: String,
        codeTTL: TimeInterval = 60,
        tokenTTL: TimeInterval = 3600,
        refreshTTL: TimeInterval = 30 * 24 * 3600,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.audience = audience
        self.codeTTL = codeTTL
        self.tokenTTL = tokenTTL
        self.refreshTTL = refreshTTL
        self.now = now
    }

    public func register(_ client: OAuthClient) {
        lock.lock(); defer { lock.unlock() }
        clients[client.id] = client
    }

    /// Front-channel pre-check for the hosted authorize page: is this exact
    /// client + redirect pair registered? Failures here must *render*, never
    /// redirect — redirecting to an unvalidated URI is an open redirect.
    public func isRegistered(clientID: String, redirectURI: String) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return clients[clientID]?.redirectURIs.contains(redirectURI) ?? false
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
    /// an access token plus a rotating refresh token. Codes are single-use and
    /// time-boxed; a failed or reused exchange is rejected as `invalidGrant`.
    public func token(
        code: String,
        codeVerifier: String,
        clientID: String,
        redirectURI: String
    ) throws -> IssuedTokens {
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

        // Each authorization starts a fresh token family; every rotation
        // stays inside it, so one stolen refresh token can kill exactly one
        // authorization's descendants and nothing else.
        return issueLocked(clientID: clientID, scopes: pending.scopes, familyID: Self.randomToken())
    }

    /// Refresh grant (RFC 6749 §6) with OAuth 2.1 rotation: every refresh
    /// token is single-use and replaced on success. Presenting an already-
    /// rotated token is treated as theft (RFC 9700 §4.14.2) — the whole
    /// family, live access tokens included, is revoked on the spot.
    public func refresh(refreshToken: String, clientID: String) throws -> IssuedTokens {
        lock.lock(); defer { lock.unlock() }

        guard let record = refreshTokens[refreshToken], record.clientID == clientID else {
            throw OAuthError.invalidGrant
        }
        guard record.expiresAt > now() else {
            refreshTokens[refreshToken] = nil
            throw OAuthError.invalidGrant
        }
        if record.rotated {
            revokeFamilyLocked(record.familyID)
            throw OAuthError.invalidGrant
        }

        refreshTokens[refreshToken]?.rotated = true
        return issueLocked(clientID: clientID, scopes: record.scopes, familyID: record.familyID)
    }

    /// Mints an access + refresh pair inside `familyID`. Caller holds the lock.
    private func issueLocked(clientID: String, scopes: Set<String>, familyID: String) -> IssuedTokens {
        let access = AccessToken(
            value: Self.randomToken(),
            clientID: clientID,
            scopes: scopes,
            audience: audience,
            expiresAt: now().addingTimeInterval(tokenTTL)
        )
        tokens[access.value] = access
        accessFamily[access.value] = familyID

        let refreshValue = Self.randomToken()
        let refreshExpiresAt = now().addingTimeInterval(refreshTTL)
        refreshTokens[refreshValue] = RefreshRecord(
            clientID: clientID,
            scopes: scopes,
            familyID: familyID,
            expiresAt: refreshExpiresAt,
            rotated: false
        )
        return IssuedTokens(access: access, refreshToken: refreshValue, refreshExpiresAt: refreshExpiresAt)
    }

    /// Reuse detected: drop every refresh token and access token descended
    /// from this authorization. Caller holds the lock.
    private func revokeFamilyLocked(_ familyID: String) {
        refreshTokens = refreshTokens.filter { $0.value.familyID != familyID }
        for (value, family) in accessFamily where family == familyID {
            tokens[value] = nil
            accessFamily[value] = nil
        }
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
