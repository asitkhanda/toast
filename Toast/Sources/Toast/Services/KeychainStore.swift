import Foundation
import Security

enum KeychainStore {
    private static let service = "com.toast.app"
    private static let account = "vercel-pat"
    private static let hardenedStorageKey = "keychainTokenHardenedV2"

    static func hasToken() -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnAttributes as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        return SecItemCopyMatching(query as CFDictionary, nil) == errSecSuccess
    }

    static func saveToken(_ token: String) throws {
        let data = Data(token.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]

        SecItemDelete(query as CFDictionary)

        var addQuery = query
        addQuery[kSecValueData as String] = data
        addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        addQuery[kSecAttrSynchronizable as String] = kCFBooleanFalse as Any
        addQuery[kSecAttrAccess as String] = try makeAccess()

        let status = SecItemAdd(addQuery as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainError.saveFailed(status)
        }
        UserDefaults.standard.set(true, forKey: hardenedStorageKey)
    }

    static func loadToken() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess,
              let data = item as? Data,
              let token = String(data: data, encoding: .utf8),
              !token.isEmpty
        else {
            return nil
        }

        migrateToHardenedStorageIfNeeded(token)
        return token
    }

    private static func migrateToHardenedStorageIfNeeded(_ token: String) {
        guard !UserDefaults.standard.bool(forKey: hardenedStorageKey) else { return }
        guard (try? saveToken(token)) != nil else { return }
        UserDefaults.standard.set(true, forKey: hardenedStorageKey)
    }

    static func deleteToken() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
        UserDefaults.standard.removeObject(forKey: hardenedStorageKey)
    }

    private static func makeAccess() throws -> SecAccess {
        var trustedApp: SecTrustedApplication?
        let trustedStatus = SecTrustedApplicationCreateFromPath(nil, &trustedApp)
        guard trustedStatus == errSecSuccess, let trustedApp else {
            throw KeychainError.accessFailed(trustedStatus)
        }

        var access: SecAccess?
        let accessStatus = SecAccessCreate(
            "Toast Vercel API token" as CFString,
            [trustedApp] as CFArray,
            &access
        )
        guard accessStatus == errSecSuccess, let access else {
            throw KeychainError.accessFailed(accessStatus)
        }
        return access
    }
}

enum KeychainError: LocalizedError {
    case saveFailed(OSStatus)
    case accessFailed(OSStatus)

    var errorDescription: String? {
        switch self {
        case .saveFailed(let status):
            "Failed to save token to Keychain (status \(status))."
        case .accessFailed(let status):
            "Failed to configure Keychain access (status \(status))."
        }
    }
}
