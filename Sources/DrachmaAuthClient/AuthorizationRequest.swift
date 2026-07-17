import Foundation
import DrachmaAuth

/// Everything the client must remember between opening the browser and
/// exchanging the code: the URL to present, plus the two one-time secrets
/// that make the round trip safe — the PKCE verifier (proof of possession,
/// RFC 7636) and the state (CSRF binding, RFC 6749 §10.12).
public struct AuthorizationRequest: Sendable, Equatable {
    public let url: URL
    public let state: String
    public let codeVerifier: String

    /// Builds the front-channel authorize URL. The verifier never leaves the
    /// device — only its S256 challenge rides the URL. `PKCE` here is the
    /// same type the server verifies with: one repo, one implementation.
    public static func make(
        configuration: OAuthClientConfiguration,
        codeVerifier: String = PKCE.generateCodeVerifier(),
        state: String = PKCE.generateCodeVerifier()
    ) -> AuthorizationRequest? {
        guard let challenge = PKCE.challenge(for: codeVerifier) else { return nil }
        var components = URLComponents(
            url: configuration.authorizeEndpoint, resolvingAgainstBaseURL: false
        )
        components?.queryItems = [
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "client_id", value: configuration.clientID),
            URLQueryItem(name: "redirect_uri", value: configuration.redirectURI),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "code_challenge_method", value: PKCE.method),
            URLQueryItem(name: "scope", value: configuration.scopes.sorted().joined(separator: " ")),
            URLQueryItem(name: "state", value: state),
        ]
        guard let url = components?.url else { return nil }
        return AuthorizationRequest(url: url, state: state, codeVerifier: codeVerifier)
    }
}

public enum AuthorizationCallbackError: Error, Equatable, Sendable {
    case malformedCallback
    /// The state echoed back doesn't match the one we sent — someone may be
    /// injecting a code that isn't ours. The only safe move is to discard.
    case stateMismatch
    /// The server declined (e.g. `access_denied` when the user taps Deny).
    case denied(String)
    case missingCode
}

public enum AuthorizationCallback {
    /// Parses the custom-scheme redirect and enforces the state round trip
    /// *before* looking at anything else in the URL.
    public static func code(from url: URL, expecting state: String) throws -> String {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            throw AuthorizationCallbackError.malformedCallback
        }
        let items = components.queryItems ?? []
        func value(_ name: String) -> String? {
            items.first(where: { $0.name == name })?.value
        }

        guard value("state") == state else {
            throw AuthorizationCallbackError.stateMismatch
        }
        if let error = value("error") {
            throw AuthorizationCallbackError.denied(error)
        }
        guard let code = value("code"), !code.isEmpty else {
            throw AuthorizationCallbackError.missingCode
        }
        return code
    }
}
