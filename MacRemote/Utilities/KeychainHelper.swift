import Foundation
import Security

struct KeychainHelper {
    
    static func savePassword(_ password: String, for host: String) {
        let key = "vnc_password_\(host)"
        
        // Delete existing item first
        deletePassword(for: host)
        
        guard let data = password.data(using: .utf8) else { return }
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecAttrService as String: "com.macremote.vnc",
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlocked
        ]
        
        let status = SecItemAdd(query as CFDictionary, nil)
        if status != errSecSuccess {
            print("Keychain: Failed to save password - \(status)")
        } else {
            print("Keychain: Password saved for \(host)")
        }
    }
    
    static func getPassword(for host: String) -> String? {
        let key = "vnc_password_\(host)"
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecAttrService as String: "com.macremote.vnc",
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        if status == errSecSuccess, let data = result as? Data {
            return String(data: data, encoding: .utf8)
        }
        
        return nil
    }
    
    static func deletePassword(for host: String) {
        let key = "vnc_password_\(host)"
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecAttrService as String: "com.macremote.vnc"
        ]
        
        SecItemDelete(query as CFDictionary)
    }
}
