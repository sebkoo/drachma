import Foundation
import Observation
import DrachmaAuth
import DrachmaAuthClient

/// Drives the Connect screen: the full OAuth 2.1 code+PKCE loop against your
/// own drachma-server — browser sheet → one-time code → token exchange →
/// Keychain → single-flight refresh — narrated step by step in `activityLog`
/// so the demo explains itself.
@Observable @MainActor
public final class ConnectViewModel {
    public enum Phase: Equatable {
        case disconnected
        case connecting
        case connected(TokenSummary)
        case failed(String)
    }

    /// What the screen shows about the stored grant — never the raw token.
    public struct TokenSummary: Equatable, Sendable {
        public let accessTokenSuffix: String
        public let scope: String
        public let expiresAt: Date
        public let hasRefreshToken: Bool
    }

    public var serverURLText: String
    public private(set) var phase: Phase = .disconnected
    public private(set) var rateText: String?
    public private(set) var activityLog: [String] = []

    public let clientID = "drachma-ios"
    public let redirectURI = "drachma://oauth/callback"
    public let scopes: Set<String> = ["rates:read"]

    private let transport: any HTTPTransport
    private let makeStore: @Sendable (String) -> any TokenStore
    private let defaults: UserDefaults
    private static let serverURLKey = "connect.serverURL"

    public init(
        transport: any HTTPTransport = URLSessionTransport(),
        makeStore: @escaping @Sendable (String) -> any TokenStore = { host in
            KeychainTokenStore(account: host)
        },
        defaults: UserDefaults = .standard
    ) {
        self.transport = transport
        self.makeStore = makeStore
        self.defaults = defaults
        self.serverURLText = defaults.string(forKey: Self.serverURLKey) ?? "http://127.0.0.1:8080"
    }

    // MARK: - The wired stack (one OAuthSession per server URL)

    private struct Stack {
        let configuration: OAuthClientConfiguration
        let tokenClient: TokenClient
        let session: OAuthSession
    }

    private var cachedStack: Stack?
    private var cachedURLText: String?

    /// One `OAuthSession` per server URL, cached: the single-flight refresh
    /// only protects callers who share the same actor instance.
    private func stack() -> Stack? {
        let text = serverURLText.trimmingCharacters(in: .whitespacesAndNewlines)
        if text == cachedURLText, let cachedStack { return cachedStack }

        guard let base = URL(string: text), let scheme = base.scheme,
              ["http", "https"].contains(scheme), base.host != nil else {
            return nil
        }
        let configuration = OAuthClientConfiguration(
            baseURL: base, clientID: clientID, redirectURI: redirectURI, scopes: scopes
        )
        let tokenClient = TokenClient(configuration: configuration, transport: transport)
        let store = makeStore(base.host ?? "drachma-server")
        let stack = Stack(
            configuration: configuration,
            tokenClient: tokenClient,
            session: OAuthSession(store: store, tokenClient: tokenClient)
        )
        cachedStack = stack
        cachedURLText = text
        return stack
    }

    // MARK: - Actions

    /// Reload whatever the Keychain still holds — connection state survives
    /// relaunch because the *tokens* survive, not any in-memory object.
    public func restore() async {
        guard case .disconnected = phase, let stack = stack() else { return }
        if let tokens = try? await stack.session.tokens() {
            phase = .connected(Self.summary(of: tokens))
            log("Restored grant from Keychain")
        }
    }

    public func connect() async {
        guard let stack = stack() else {
            phase = .failed("Enter a valid http(s) server URL first.")
            return
        }
        defaults.set(serverURLText, forKey: Self.serverURLKey)

        guard #available(iOS 17.4, macOS 14.4, *) else {
            phase = .failed("The system sign-in sheet API used here needs iOS 17.4+.")
            return
        }
        guard let request = AuthorizationRequest.make(configuration: stack.configuration),
              let callbackScheme = stack.configuration.callbackScheme else {
            phase = .failed("Couldn't build the authorize URL.")
            return
        }

        phase = .connecting
        rateText = nil
        log("Opening system auth sheet (ASWebAuthenticationSession)")
        do {
            let callback = try await WebAuthenticator().authenticate(
                url: request.url, callbackScheme: callbackScheme
            )
            log("Callback caught on \(callbackScheme):// — checking state (CSRF)")
            let code = try AuthorizationCallback.code(from: callback, expecting: request.state)
            log("Exchanging one-time code + PKCE verifier at /oauth/token")
            let tokens = try await stack.tokenClient.exchange(
                code: code, codeVerifier: request.codeVerifier
            )
            try await stack.session.adopt(tokens)
            phase = .connected(Self.summary(of: tokens))
            log("Access + refresh token stored in Keychain")
        } catch WebAuthenticator.WebAuthError.userCancelled {
            phase = .disconnected
            log("Sign-in sheet dismissed")
        } catch {
            let message = Self.message(for: error)
            phase = .failed(message)
            log("Connect failed: \(message)")
        }
    }

    /// Force a rotation so the demo can *show* refresh-token rotation:
    /// watch the access-token suffix change and the old refresh token die.
    public func refreshNow() async {
        guard let stack = stack() else { return }
        do {
            log("POST /oauth/token grant_type=refresh_token")
            let fresh = try await stack.session.refreshNow()
            phase = .connected(Self.summary(of: fresh))
            log("Rotated — new access + refresh token stored, old refresh token now dead")
        } catch OAuthSessionError.notConnected {
            phase = .disconnected
            log("No grant to refresh")
        } catch {
            let message = Self.message(for: error)
            phase = .failed(message)
            log("Refresh failed: \(message)")
        }
    }

    /// The payoff: a protected call. `validAccessToken()` transparently
    /// refreshes first when the stored token is stale.
    public func fetchRate(base: String = "USD", quote: String = "EUR") async {
        guard let stack = stack() else { return }
        do {
            let token = try await stack.session.validAccessToken()

            var components = URLComponents(
                url: stack.configuration.baseURL.appendingPathComponent("v1/rates"),
                resolvingAgainstBaseURL: false
            )
            components?.queryItems = [
                URLQueryItem(name: "base", value: base),
                URLQueryItem(name: "quote", value: quote),
            ]
            guard let url = components?.url else { return }

            var request = URLRequest(url: url)
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            let (data, status) = try await transport.send(request)
            guard status == 200 else {
                rateText = nil
                log("GET /v1/rates → \(status)")
                return
            }

            struct Wire: Decodable {
                let base: String
                let quote: String
                let rate: Double
                let rateDate: String
                let source: String
            }
            let wire = try JSONDecoder().decode(Wire.self, from: data)
            rateText = "1 \(wire.base) = \(wire.rate) \(wire.quote) · \(wire.source) · \(wire.rateDate)"
            log("GET /v1/rates → 200 (Bearer accepted, scope rates:read)")

            if let tokens = try? await stack.session.tokens() {
                phase = .connected(Self.summary(of: tokens))
            }
        } catch OAuthSessionError.notConnected {
            phase = .disconnected
            log("Session expired and couldn't refresh — connect again")
        } catch {
            log("Rate fetch failed: \(Self.message(for: error))")
        }
    }

    public func disconnect() async {
        guard let stack = stack() else { return }
        try? await stack.session.signOut()
        phase = .disconnected
        rateText = nil
        log("Keychain entry removed — disconnected (server-side revocation: future work)")
    }

    // MARK: - Presentation helpers

    private static func summary(of tokens: OAuthTokens) -> TokenSummary {
        TokenSummary(
            accessTokenSuffix: String(tokens.accessToken.suffix(6)),
            scope: tokens.scope,
            expiresAt: tokens.expiresAt,
            hasRefreshToken: tokens.refreshToken != nil
        )
    }

    static func message(for error: Error) -> String {
        switch error {
        case AuthorizationCallbackError.stateMismatch:
            return "State mismatch — possible CSRF, sign-in discarded."
        case AuthorizationCallbackError.denied(let reason):
            return "Server declined: \(reason)."
        case AuthorizationCallbackError.missingCode, AuthorizationCallbackError.malformedCallback:
            return "The callback didn't carry a usable code."
        case TokenClientError.badResponse(let status, let oauthError):
            return "Token endpoint said \(status) (\(oauthError ?? "no error code"))."
        case TokenClientError.malformedBody:
            return "Couldn't parse the token response."
        default:
            return "Couldn't reach the server. Is drachma-server running at that URL?"
        }
    }

    private func log(_ line: String) {
        activityLog.append(line)
    }
}
