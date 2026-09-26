import Foundation
import Security
import UIKit

/// No account or network access. Exercise the same generic-password storage used by Auth SDKs.
@main
final class SimulatorKeychainProbe: UIResponder, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "FitFight.AuthStorageProbe",
            kSecAttrAccount as String: UUID().uuidString,
        ]
        var insert = query
        insert[kSecValueData as String] = Data("simulator-storage-probe".utf8)
        insert[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let added = SecItemAdd(insert as CFDictionary, nil)
        let read = SecItemCopyMatching(query as CFDictionary, nil)
        let deleted = SecItemDelete(query as CFDictionary)
        let result = ["add": added, "read": read, "delete": deleted]
        let output = URL.documentsDirectory.appendingPathComponent("keychain-probe.json")
        do {
            try JSONEncoder().encode(result).write(to: output, options: .atomic)
        } catch {
            fatalError("Could not record the simulator keychain probe: \(error)")
        }
        return true
    }
}
