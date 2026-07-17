import XCTest
import DrachmaAuth
@testable import DrachmaAuthClient

private let configuration = OAuthClientConfiguration(
    baseURL: URL(string: "http://127.0.0.1:8080")!,
    clientID: "drachma-ios",
    redirectURI: "drachma://oauth/callback",
    scopes: ["rates:read"]
)

final class AuthorizationFlowTests: XCTestCase {

    func testAuthorizeURLCarriesTheStandardParameters() throws {
        let request = try XCTUnwrap(AuthorizationRequest.make(configuration: configuration))
        let components = try XCTUnwrap(URLComponents(url: request.url, resolvingAgainstBaseURL: false))
        var query: [String: String] = [:]
        for item in components.queryItems ?? [] { query[item.name] = item.value }

        XCTAssertEqual(components.path, "/oauth/authorize")
        XCTAssertEqual(query["response_type"], "code")
        XCTAssertEqual(query["client_id"], "drachma-ios")
        XCTAssertEqual(query["redirect_uri"], "drachma://oauth/callback")
        XCTAssertEqual(query["code_challenge_method"], "S256")
        XCTAssertEqual(query["scope"], "rates:read")
        XCTAssertEqual(query["state"], request.state)
    }

    func testChallengeInTheURLDerivesFromTheVerifierWeKeep() throws {
        let request = try XCTUnwrap(AuthorizationRequest.make(configuration: configuration))
        let components = try XCTUnwrap(URLComponents(url: request.url, resolvingAgainstBaseURL: false))
        let challenge = components.queryItems?.first { $0.name == "code_challenge" }?.value

        // The URL carries SHA256(verifier); the verifier itself never appears.
        XCTAssertEqual(challenge, PKCE.challenge(for: request.codeVerifier))
        XCTAssertFalse(request.url.absoluteString.contains(request.codeVerifier))
    }

    func testFreshSecretsEveryAttempt() throws {
        let first = try XCTUnwrap(AuthorizationRequest.make(configuration: configuration))
        let second = try XCTUnwrap(AuthorizationRequest.make(configuration: configuration))
        XCTAssertNotEqual(first.state, second.state)
        XCTAssertNotEqual(first.codeVerifier, second.codeVerifier)
    }

    // MARK: - Callback parsing

    func testHappyCallbackYieldsTheCode() throws {
        let url = URL(string: "drachma://oauth/callback?code=abc123&state=expected")!
        XCTAssertEqual(try AuthorizationCallback.code(from: url, expecting: "expected"), "abc123")
    }

    func testStateMismatchIsRejectedBeforeAnythingElse() {
        // Even a "successful looking" callback with a code dies on bad state —
        // that's the CSRF defense doing its one job.
        let url = URL(string: "drachma://oauth/callback?code=abc123&state=forged")!
        XCTAssertThrowsError(try AuthorizationCallback.code(from: url, expecting: "expected")) {
            XCTAssertEqual($0 as? AuthorizationCallbackError, .stateMismatch)
        }
    }

    func testServerDenialSurfacesTheErrorCode() {
        let url = URL(string: "drachma://oauth/callback?error=access_denied&state=s")!
        XCTAssertThrowsError(try AuthorizationCallback.code(from: url, expecting: "s")) {
            XCTAssertEqual($0 as? AuthorizationCallbackError, .denied("access_denied"))
        }
    }

    func testMissingCodeIsAnError() {
        let url = URL(string: "drachma://oauth/callback?state=s")!
        XCTAssertThrowsError(try AuthorizationCallback.code(from: url, expecting: "s")) {
            XCTAssertEqual($0 as? AuthorizationCallbackError, .missingCode)
        }
    }
}
