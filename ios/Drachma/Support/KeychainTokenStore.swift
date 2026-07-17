import Foundation
import DrachmaAuthClient
#if canImport(Security)
import Security
#endif

public enum KeychainError: Error, Equatable {
    case status(Int32)
}

/// Tokens live in the Keychain, not UserDefaults: encrypted at rest, gone
/// with the app, and never in a plist a backup tool can read.
/// `AfterFirstUnlockThisDeviceOnly` keeps them available for background
/// refresh while opting out of iCloud Keychain sync — a bearer token for
/// *this* device shouldn't quietly replicate to every device on the account.
public struct KeychainTokenStore: TokenStore {
    private let service: String
    private let account: String

    /// One item per server (`account` = host), so pointing the Connect screen
    /// at a different drachma-server keeps grants separate.
    public init(service: String = "dev.sebkoo.drachma.oauth", account: String = "drachma-server") {
        self.service = service
        self.account = account
    }

#if canImport(Security)
    public func load() throws -> OAuthTokens? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status != errSecItemNotFound else { return nil }
        guard status == errSecSuccess, let data = item as? Data else {
            throw KeychainError.status(status)
        }
        return try JSONDecoder().decode(OAuthTokens.self, from: data)
    }

    public func save(_ tokens: OAuthTokens) throws {
        let data = try JSONEncoder().encode(tokens)

        var add = baseQuery
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly

        let status = SecItemAdd(add as CFDictionary, nil)
        if status == errSecDuplicateItem {
            let update = [kSecValueData as String: data]
            let updateStatus = SecItemUpdate(baseQuery as CFDictionary, update as CFDictionary)
            guard updateStatus == errSecSuccess else { throw KeychainError.status(updateStatus) }
        } else {
            guard status == errSecSuccess else { throw KeychainError.status(status) }
        }
    }

    public func clear() throws {
        let status = SecItemDelete(baseQuery as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.status(status)
        }
    }

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }
#else
    // No Keychain off Apple platforms; DrachmaApp never builds there.
    public func load() throws -> OAuthTokens? { nil }
    public func save(_ tokens: OAuthTokens) throws {}
    public func clear() throws {}
#endif
}
