import Foundation
import Security

struct SessionVault {
    let service: String
    private var query: [String: Any] { [kSecClass as String:kSecClassGenericPassword, kSecAttrService as String:service, kSecAttrAccount as String:"session"] }
    func load() throws -> AuthSession? {
        var q = query; q[kSecReturnData as String] = true; q[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(q as CFDictionary,&result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else { throw UserFacingError(message:"Le trousseau est temporairement indisponible.") }
        return try JSONDecoder().decode(AuthSession.self,from:data)
    }
    func save(_ session: AuthSession) throws {
        let attributes: [String: Any] = [kSecValueData as String:try JSONEncoder().encode(session), kSecAttrAccessible as String:kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var q = query; attributes.forEach { q[$0.key] = $0.value }
            guard SecItemAdd(q as CFDictionary,nil) == errSecSuccess else { throw UserFacingError(message:"Impossible de sécuriser la connexion sur cet appareil.") }
        } else if status != errSecSuccess { throw UserFacingError(message:"Impossible de mettre à jour la connexion.") }
    }
    func delete() throws {
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw UserFacingError(message:"Impossible d’effacer la connexion de cet appareil.") }
    }
}
