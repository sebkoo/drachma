import Foundation
import Hummingbird
import HTTPTypes
import NIOCore
import DrachmaCore
import DrachmaAuth

// Wire-format payloads for the RESTful API.

struct HealthResponse: Encodable {
    var status = "ok"
    var service = "drachma-server"
}

/// RFC 9728 Protected Resource Metadata — how a client discovers the auth server.
struct ProtectedResourceMetadata: Encodable {
    let resource: String
    let authorizationServers: [String]
    let scopesSupported: [String]
    let bearerMethodsSupported: [String]

    enum CodingKeys: String, CodingKey {
        case resource
        case authorizationServers = "authorization_servers"
        case scopesSupported = "scopes_supported"
        case bearerMethodsSupported = "bearer_methods_supported"
    }
}

struct AuthorizeRequest: Decodable {
    let clientID: String
    let redirectURI: String
    let codeChallenge: String
    let codeChallengeMethod: String
    let scope: [String]
}

struct AuthorizeResponse: Encodable {
    let code: String
}

/// One envelope, two grants (authorization_code | refresh_token): everything
/// beyond `grantType` + `clientID` is optional and validated per grant.
struct TokenRequest: Decodable {
    let grantType: String
    let clientID: String
    let code: String?
    let codeVerifier: String?
    let redirectURI: String?
    let refreshToken: String?
}

struct TokenResponse: Encodable {
    let accessToken: String
    let tokenType: String
    let expiresIn: Int
    let scope: String
    let refreshToken: String?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case tokenType = "token_type"
        case expiresIn = "expires_in"
        case scope
        case refreshToken = "refresh_token"
    }
}

/// The front-channel authorize parameters (RFC 6749 §4.1.1), read from the
/// GET query string and echoed through the consent form's hidden fields.
struct AuthorizePageParams {
    let responseType: String
    let clientID: String
    let redirectURI: String
    let codeChallenge: String
    let codeChallengeMethod: String
    let scopeRaw: String
    let state: String?

    var scopes: Set<String> {
        Set(scopeRaw.split(separator: " ").map(String.init))
    }

    init?(_ value: (String) -> String?) {
        guard
            let clientID = value("client_id"), !clientID.isEmpty,
            let redirectURI = value("redirect_uri"), !redirectURI.isEmpty,
            let codeChallenge = value("code_challenge"), !codeChallenge.isEmpty
        else { return nil }

        self.responseType = value("response_type") ?? ""
        self.clientID = clientID
        self.redirectURI = redirectURI
        self.codeChallenge = codeChallenge
        self.codeChallengeMethod = value("code_challenge_method") ?? ""
        self.scopeRaw = value("scope") ?? ""
        self.state = value("state")
    }
}

struct APIError: Encodable {
    let error: String
    let errorDescription: String?

    enum CodingKeys: String, CodingKey {
        case error
        case errorDescription = "error_description"
    }
}

struct RateResponse: Encodable {
    let base: String
    let quote: String
    let rate: Decimal
    let rateDate: String
    let source: String
    let disclaimer = "Reference rate, not a tradable quote."
}
