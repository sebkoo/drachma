import XCTest
@testable import DrachmaAuth

final class PKCETests: XCTestCase {
    /// RFC 7636 Appendix B canonical test vector — proves the S256 challenge
    /// is spec-correct, not just internally consistent.
    func testRFC7636KnownAnswerVector() {
        let verifier = "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk"
        let expected = "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM"

        XCTAssertEqual(PKCE.challenge(for: verifier), expected)
        XCTAssertTrue(PKCE.verify(verifier: verifier, matches: expected))
    }

    func testPlainMethodIsRejected() {
        // OAuth 2.1 forbids the `plain` challenge method.
        XCTAssertNil(PKCE.challenge(for: "anything", method: "plain"))
        XCTAssertFalse(PKCE.verify(verifier: "anything", matches: "anything", method: "plain"))
    }

    func testGeneratedVerifierIsUrlSafeAndHighEntropy() {
        let verifier = PKCE.generateCodeVerifier()
        let allowed = CharacterSet(charactersIn:
            "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_")
        XCTAssertTrue(verifier.unicodeScalars.allSatisfy(allowed.contains))
        XCTAssertGreaterThanOrEqual(verifier.count, 43) // 32 bytes → 43 base64url chars
        XCTAssertNotEqual(PKCE.generateCodeVerifier(), verifier)
    }

    func testWrongVerifierFailsVerification() {
        let challenge = PKCE.challenge(for: "correct-verifier")!
        XCTAssertFalse(PKCE.verify(verifier: "wrong-verifier", matches: challenge))
    }
}
