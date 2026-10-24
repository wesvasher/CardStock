import Foundation
import Security

/// Stores GitHub tokens in the login Keychain, one per GitHub account
/// (keyed by the account's login). Tokens are per Mac, never in a site
/// folder, so another Mac signs in on its own.
enum Keychain {
    private static let service = "com.wesvasher.cardstock.github"
    /// Where the single token lived before CardStock supported several accounts.
    static let legacyAccount = "personal-access-token"

    private static func query(_ account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    /// Logins with a saved token (not including the legacy entry).
    static func savedLogins() -> [String] {
        let search: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecReturnAttributes as String: true,
            kSecMatchLimit as String: kSecMatchLimitAll,
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(search as CFDictionary, &result) == errSecSuccess,
              let items = result as? [[String: Any]] else { return [] }
        return items.compactMap { $0[kSecAttrAccount as String] as? String }
            .filter { $0 != legacyAccount }
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    static func token(for login: String) -> String? {
        var search = query(login)
        search[kSecReturnData as String] = true
        search[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        guard SecItemCopyMatching(search as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func save(_ token: String, for login: String) throws {
        delete(login)
        var item = query(login)
        item[kSecValueData as String] = Data(token.utf8)
        item[kSecAttrLabel as String] = "CardStock GitHub token (\(login))"
        let status = SecItemAdd(item as CFDictionary, nil)
        guard status == errSecSuccess else {
            let message = SecCopyErrorMessageString(status, nil) as String? ?? "error \(status)"
            throw SiteError("Couldn't save the token to the Keychain: \(message)")
        }
    }

    static func delete(_ login: String) {
        SecItemDelete(query(login) as CFDictionary)
    }
}
