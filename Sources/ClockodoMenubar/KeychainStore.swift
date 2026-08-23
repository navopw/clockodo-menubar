import Foundation
import Security

enum KeychainError: LocalizedError {
    case operationFailed(OSStatus)

    var errorDescription: String? {
        switch self {
        case let .operationFailed(status):
            return "Could not access the macOS Keychain (status \(status))."
        }
    }
}

protocol CredentialStore: Sendable {
    func read(account: String) throws -> String?
    func save(_ value: String, account: String) throws
    func delete(account: String) throws
}

struct KeychainStore: CredentialStore {
    private let service = "com.clockodo.menubar.credentials"

    func read(account: String) throws -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status != errSecItemNotFound else { return nil }
        guard status == errSecSuccess, let data = result as? Data else {
            throw KeychainError.operationFailed(status)
        }
        return String(data: data, encoding: .utf8)
    }

    func save(_ value: String, account: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let attributes: [String: Any] = [
            kSecValueData as String: Data(value.utf8),
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]

        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecItemNotFound {
            var item = query
            item.merge(attributes) { _, new in new }
            let addStatus = SecItemAdd(item as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw KeychainError.operationFailed(addStatus)
            }
        } else if updateStatus != errSecSuccess {
            throw KeychainError.operationFailed(updateStatus)
        }
    }

    func delete(account: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.operationFailed(status)
        }
    }
}
