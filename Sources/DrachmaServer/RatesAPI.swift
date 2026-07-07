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

struct TokenRequest: Decodable {
    let grantType: String
    let code: String
    let codeVerifier: String
    let clientID: String
    let redirectURI: String
}

struct TokenResponse: Encodable {
    let accessToken: String
    let tokenType: String
    let expiresIn: Int
    let scope: String

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case tokenType = "token_type"
        case expiresIn = "expires_in"
        case scope
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
