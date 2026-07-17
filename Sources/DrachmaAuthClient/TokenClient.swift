import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// The transport seam: URLSession in the app, an in-process router adapter in
/// tests — so the token protocol is testable without sockets.
public protocol HTTPTransport: Sendable {
    /// Returns (body, HTTP status).
    func send(_ request: URLRequest) async throws -> (Data, Int)
}

public struct URLSessionTransport: HTTPTransport {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func send(_ request: URLRequest) async throws -> (Data, Int) {
        // Continuation over dataTask instead of the async overloads: identical
        // on Apple platforms, and it keeps this target building on Linux.
        try await withCheckedThrowingContinuation { continuation in
            session.dataTask(with: request) { data, response, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                continuation.resume(returning: (data ?? Data(), status))
            }.resume()
        }
    }
}

/// The client's view of a grant: what to send (`accessToken`), how to renew
/// (`refreshToken`), and when to stop trusting it (`expiresAt`, computed from
/// `expires_in` at receipt — the wire never carries absolute times).
public struct OAuthTokens: Codable, Equatable, Sendable {
    public let accessToken: String
    public let refreshToken: String?
    public let scope: String
    public let expiresAt: Date

    public init(accessToken: String, refreshToken: String?, scope: String, expiresAt: Date) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.scope = scope
        self.expiresAt = expiresAt
    }

    /// Fresh enough to put on a request, with `leeway` seconds of margin so a
    /// token doesn't expire mid-flight between client check and server check.
    public func isFresh(leeway: TimeInterval = 30, now: Date = Date()) -> Bool {
        expiresAt.timeIntervalSince(now) > leeway
    }
}

public enum TokenClientError: Error, Equatable, Sendable {
    /// Non-200 from the token endpoint; carries the OAuth error code when the
    /// body had one (`invalid_grant`, `unsupported_grant_type`, …).
    case badResponse(status: Int, oauthError: String?)
    case malformedBody
}

/// The two back-channel calls of the code+PKCE flow. Wire format matches
/// drachma-server's RatesAPI: camelCase JSON in, snake_case JSON out.
public struct TokenClient: Sendable {
    private let configuration: OAuthClientConfiguration
    private let transport: any HTTPTransport
    private let now: @Sendable () -> Date

    public init(
        configuration: OAuthClientConfiguration,
        transport: any HTTPTransport = URLSessionTransport(),
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.configuration = configuration
        self.transport = transport
        self.now = now
    }

    /// Code exchange (RFC 6749 §4.1.3): the moment PKCE pays off — the code
    /// alone is worthless without the verifier that never left the device.
    public func exchange(code: String, codeVerifier: String) async throws -> OAuthTokens {
        try await request([
            "grantType": "authorization_code",
            "clientID": configuration.clientID,
            "redirectURI": configuration.redirectURI,
            "code": code,
            "codeVerifier": codeVerifier,
        ])
    }

    /// Refresh grant (RFC 6749 §6). The server rotates: the token sent here
    /// dies with this call and the reply carries its replacement.
    public func refresh(refreshToken: String) async throws -> OAuthTokens {
        try await request([
            "grantType": "refresh_token",
            "clientID": configuration.clientID,
            "refreshToken": refreshToken,
        ])
    }

    private func request(_ body: [String: String]) async throws -> OAuthTokens {
        var request = URLRequest(url: configuration.tokenEndpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONEncoder().encode(body)

        let (data, status) = try await transport.send(request)
        guard status == 200 else {
            let wire = try? JSONDecoder().decode(WireError.self, from: data)
            throw TokenClientError.badResponse(status: status, oauthError: wire?.error)
        }
        guard let wire = try? JSONDecoder().decode(WireTokenResponse.self, from: data) else {
            throw TokenClientError.malformedBody
        }
        return OAuthTokens(
            accessToken: wire.accessToken,
            refreshToken: wire.refreshToken,
            scope: wire.scope,
            expiresAt: now().addingTimeInterval(TimeInterval(wire.expiresIn))
        )
    }

    private struct WireTokenResponse: Decodable {
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

    private struct WireError: Decodable {
        let error: String
    }
}
