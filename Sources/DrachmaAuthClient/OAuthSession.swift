import Foundation

public enum OAuthSessionError: Error, Equatable, Sendable {
    /// Nothing stored, or the stored grant can no longer be renewed —
    /// the UI's cue to show Connect again.
    case notConnected
}

/// The client-side token lifecycle, serialized by an actor: hand out the
/// access token while it's fresh, refresh it exactly once when it isn't.
/// Concurrent callers join the same in-flight refresh instead of racing —
/// refresh tokens are single-use, so two parallel refreshes would trip the
/// server's reuse detection and revoke the whole family.
public actor OAuthSession {
    private let store: any TokenStore
    private let tokenClient: TokenClient
    private let leeway: TimeInterval
    private let now: @Sendable () -> Date
    private var refreshTask: Task<OAuthTokens, Error>?

    public init(
        store: any TokenStore,
        tokenClient: TokenClient,
        leeway: TimeInterval = 30,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.store = store
        self.tokenClient = tokenClient
        self.leeway = leeway
        self.now = now
    }

    /// The stored grant, if any — for showing state, never for sending.
    public func tokens() throws -> OAuthTokens? {
        try store.load()
    }

    /// Adopt a freshly exchanged grant (post-connect).
    public func adopt(_ tokens: OAuthTokens) throws {
        try store.save(tokens)
    }

    public func signOut() throws {
        refreshTask?.cancel()
        refreshTask = nil
        try store.clear()
    }

    /// A bearer token that's safe to put on a request right now — refreshed
    /// behind the scenes when the stored one is within `leeway` of expiry.
    public func validAccessToken() async throws -> String {
        guard let current = try store.load() else {
            throw OAuthSessionError.notConnected
        }
        if current.isFresh(leeway: leeway, now: now()) {
            return current.accessToken
        }
        return try await refreshedTokens(from: current).accessToken
    }

    /// Force a rotation (the Connect screen's "Rotate now" button).
    @discardableResult
    public func refreshNow() async throws -> OAuthTokens {
        guard let current = try store.load() else {
            throw OAuthSessionError.notConnected
        }
        return try await refreshedTokens(from: current)
    }

    private func refreshedTokens(from current: OAuthTokens) async throws -> OAuthTokens {
        // Single flight: whoever finds a refresh in progress awaits it.
        if let running = refreshTask {
            return try await running.value
        }
        // Actor reentrancy: this caller may have been suspended while another
        // finished a refresh and cleared the task. If the store already holds
        // something newer and fresh, use it — starting a second refresh with
        // the *old* (now rotated) token would look like theft to the server.
        if let stored = try store.load(), stored != current,
           stored.isFresh(leeway: leeway, now: now()) {
            return stored
        }
        guard let refreshToken = current.refreshToken else {
            try? store.clear()
            throw OAuthSessionError.notConnected
        }

        let client = tokenClient
        let task = Task { try await client.refresh(refreshToken: refreshToken) }
        refreshTask = task
        defer { refreshTask = nil }

        do {
            let fresh = try await task.value
            try store.save(fresh)
            return fresh
        } catch let error as TokenClientError {
            // invalid_grant == the server no longer honors this refresh token
            // (expired, rotated elsewhere, family revoked). Locally that means
            // signed out; a transport blip must NOT wipe the Keychain.
            if case .badResponse(_, let oauthError) = error, oauthError == "invalid_grant" {
                try? store.clear()
            }
            throw error
        }
    }
}
