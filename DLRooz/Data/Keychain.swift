import Foundation
import Security

/// Generic-password Keychain storage. tvOS has no durable app file storage, so secrets and the
/// site session (cookies) live here: they survive restarts and are never in a backup in clear text.
enum Keychain {
    private static let service = "app.dlrooz.tv"

    static func set(_ data: Data?, for key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
        SecItemDelete(query as CFDictionary)
        guard let data else { return }
        var add = query
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(add as CFDictionary, nil)
    }

    static func data(for key: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var out: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &out) == errSecSuccess else { return nil }
        return out as? Data
    }

    static func string(for key: String) -> String {
        data(for: key).flatMap { String(data: $0, encoding: .utf8) } ?? ""
    }

    static func setString(_ value: String, for key: String) {
        set(value.isEmpty ? nil : Data(value.utf8), for: key)
    }

    static func codable<T: Decodable>(_ type: T.Type, for key: String) -> T? {
        data(for: key).flatMap { try? JSONDecoder().decode(T.self, from: $0) }
    }

    static func setCodable<T: Encodable>(_ value: T?, for key: String) {
        set(value.flatMap { try? JSONEncoder().encode($0) }, for: key)
    }
}
