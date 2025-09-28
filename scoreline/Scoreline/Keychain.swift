//
//  Keychain.swift
//  Scoreline
//
//  Created by Mehul Jasti on 9/27/25.
//

import Foundation
import Security

@MainActor
enum Keychain {
    static func set(_ value: Data, for key: String) {
        let q: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key
        ]
        SecItemDelete(q as CFDictionary)
        var attrs = q
        attrs[kSecValueData as String] = value
        attrs[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(attrs as CFDictionary, nil)
    }

    static func get(_ key: String) -> Data? {
        let q: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var out: CFTypeRef?
        let status = SecItemCopyMatching(q as CFDictionary, &out)
        guard status == errSecSuccess else { return nil }
        return out as? Data
    }

    static func remove(_ key: String) {
        let q: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key
        ]
        SecItemDelete(q as CFDictionary)
    }
}

/// Namespaced keys (not top-level)
enum KCKey {
    static let accessToken  = "scoreline.accessToken"
    static let refreshToken = "scoreline.refreshToken"
    static let appleUserID  = "scoreline.appleUserID"
    static let cachedUser   = "scoreline.cachedUser"
}
