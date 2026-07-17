import Foundation

/// The client half of the registration the server holds: same client id,
/// same redirect, same scopes. Drift on either side breaks the handshake —
/// which is why the e2e test drives both ends from this one struct.
public struct OAuthClientConfiguration: Sendable, Equatable {
    public let baseURL: URL
    public let clientID: String
    public let redirectURI: String
    public let scopes: Set<String>

    public init(baseURL: URL, clientID: String, redirectURI: String, scopes: Set<String>) {
        self.baseURL = baseURL
        self.clientID = clientID
        self.redirectURI = redirectURI
        self.scopes = scopes
    }

    public var authorizeEndpoint: URL {
        baseURL.appendingPathComponent("oauth/authorize")
    }

    public var tokenEndpoint: URL {
        baseURL.appendingPathComponent("oauth/token")
    }

    /// The custom scheme ASWebAuthenticationSession should intercept
    /// ("drachma" for drachma://oauth/callback).
    public var callbackScheme: String? {
        URLComponents(string: redirectURI)?.scheme
    }
}
