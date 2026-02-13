import Foundation
import Security

enum KeychainError: Error, LocalizedError {
    case unexpectedData
    case unableToSave(OSStatus)
    case unableToRead(OSStatus)
    case unableToDelete(OSStatus)

    var errorDescription: String? {
        switch self {
        case .unexpectedData:
            return "Unexpected data format in Keychain"
        case .unableToSave(let status):
            return "Unable to save to Keychain: \(SecCopyErrorMessageString(status, nil) ?? "unknown" as CFString)"
        case .unableToRead(let status):
            return "Unable to read from Keychain: \(SecCopyErrorMessageString(status, nil) ?? "unknown" as CFString)"
        case .unableToDelete(let status):
            return "Unable to delete from Keychain: \(SecCopyErrorMessageString(status, nil) ?? "unknown" as CFString)"
        }
    }
}

enum KeychainHelper {
    private static let service = "macquitto"
    private static let account = "mqtt_password"

    static func savePassword(_ password: String) throws {
        guard let data = password.data(using: .utf8) else {
            throw KeychainError.unexpectedData
        }

        // Delete any existing item first to avoid ACL mismatch issues
        // (e.g., item created by a differently-signed build)
        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(deleteQuery as CFDictionary)

        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlocked,
        ]

        let status = SecItemAdd(addQuery as CFDictionary, nil)

        guard status == errSecSuccess else {
            throw KeychainError.unableToSave(status)
        }

        Log.info("MQTT password saved to Keychain", category: .config)
    }

    static func readPassword() throws -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlocked,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        if status == errSecItemNotFound {
            return nil
        }

        guard status == errSecSuccess else {
            throw KeychainError.unableToRead(status)
        }

        guard let data = result as? Data,
              let password = String(data: data, encoding: .utf8)
        else {
            throw KeychainError.unexpectedData
        }

        return password
    }

    static func deletePassword() throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]

        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unableToDelete(status)
        }

        Log.info("MQTT password deleted from Keychain", category: .config)
    }
}
