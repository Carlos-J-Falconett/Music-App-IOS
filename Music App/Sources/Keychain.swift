import Foundation
import Security

/// The media server's device token, kept in the iOS Keychain (never in the source,
/// Info.plist, UserDefaults or files). It's pasted once in Settings → Media Server.
/// Readable after the first unlock, so a sync can still finish if the screen locks.
nonisolated enum ServerTokenStore {
    private static let service = (Bundle.main.bundleIdentifier ?? "Sun") + ".media-server"
    private static let account = "device-token"

    static var token: String? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static var hasToken: Bool { token?.isEmpty == false }

    /// Saves (or replaces) the token. Surrounding spaces and line breaks from pasting are removed.
    @discardableResult
    static func save(_ token: String) -> Bool {
        let cleaned = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty, let data = cleaned.data(using: .utf8) else { return false }
        SecItemDelete(baseQuery as CFDictionary)
        var item = baseQuery
        item[kSecValueData as String] = data
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        return SecItemAdd(item as CFDictionary, nil) == errSecSuccess
    }

    static func remove() {
        SecItemDelete(baseQuery as CFDictionary)
    }

    private static var baseQuery: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }
}
