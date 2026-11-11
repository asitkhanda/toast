import Foundation
import Security

enum KeychainStore {
    private static let service = "com.toast.app"
    static func hasToken(for provider: DeploymentProvider = .vercel) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: provider.keychainAccount,
            kSecReturnAttributes as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        return SecItemCopyMatching(query as CFDictionary, nil) == errSecSuccess
    }

    static func saveToken(_ token: String, for provider: DeploymentProvider = .vercel) throws {
        let data = Data(token.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: provider.keychainAccount,
        ]

        SecItemDelete(query as CFDictionary)

        var addQuery = query
        addQuery[kSecValueData as String] = data
        addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        addQuery[kSecAttrSynchronizable as String] = kCFBooleanFalse as Any
        #if !APPSTORE
        addQuery[kSecAttrAccess as String] = try makeAccess(for: provider)
        #endif

        let status = SecItemAdd(addQuery as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainError.saveFailed(status)
        }
        UserDefaults.standard.set(true, forKey: provider.hardenedStorageKey)
    }

    static func loadToken(for provider: DeploymentProvider = .vercel) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: provider.keychainAccount,
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

        migrateToHardenedStorageIfNeeded(token, for: provider)
        return token
    }

    private static func migrateToHardenedStorageIfNeeded(_ token: String, for provider: DeploymentProvider) {
        guard !UserDefaults.standard.bool(forKey: provider.hardenedStorageKey) else { return }
        guard (try? saveToken(token, for: provider)) != nil else { return }
        UserDefaults.standard.set(true, forKey: provider.hardenedStorageKey)
    }

    static func deleteToken(for provider: DeploymentProvider = .vercel) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: provider.keychainAccount,
        ]
        SecItemDelete(query as CFDictionary)
        UserDefaults.standard.removeObject(forKey: provider.hardenedStorageKey)
    }

    private static func makeAccess(for provider: DeploymentProvider) throws -> SecAccess {
        #if APPSTORE
        throw KeychainError.accessFailed(errSecUnimplemented)
        #else
        var trustedApp: SecTrustedApplication?
        let trustedStatus = SecTrustedApplicationCreateFromPath(nil, &trustedApp)
        guard trustedStatus == errSecSuccess, let trustedApp else {
            throw KeychainError.accessFailed(trustedStatus)
        }

        var access: SecAccess?
        let accessStatus = SecAccessCreate(
            "Toast \(provider.displayName) API token" as CFString,
            [trustedApp] as CFArray,
            &access
        )
        guard accessStatus == errSecSuccess, let access else {
            throw KeychainError.accessFailed(accessStatus)
        }
        return access
        #endif
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
