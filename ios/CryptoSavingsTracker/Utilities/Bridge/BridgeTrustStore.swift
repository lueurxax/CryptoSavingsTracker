import Foundation
import Security

protocol BridgeTrustStoring: AnyObject {
    func loadTrustedDevices() -> [TrustedBridgeDevice]
    func upsert(_ device: TrustedBridgeDevice) throws
    func revoke(deviceID: UUID) throws
    func removeAll() throws
}

final class BridgeTrustStore: BridgeTrustStoring {
    private let service = "com.cryptosavingstracker.bridge.trust"
    private let account = "trustedDevices"
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    func loadTrustedDevices() -> [TrustedBridgeDevice] {
        guard let data = try? readData() else { return [] }
        return (try? decoder.decode([TrustedBridgeDevice].self, from: data)) ?? []
    }

    func upsert(_ device: TrustedBridgeDevice) throws {
        var devices = loadTrustedDevices()
        if let index = devices.firstIndex(where: { $0.id == device.id }) {
            devices[index] = device
        } else {
            devices.append(device)
        }
        try write(devices)
    }

    func revoke(deviceID: UUID) throws {
        var devices = loadTrustedDevices()
        guard let index = devices.firstIndex(where: { $0.id == deviceID }) else { return }
        devices[index].trustState = .revoked
        try write(devices)
    }

    func removeAll() throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: account,
            kSecAttrService as String: service
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainManager.KeychainError.unhandledError(status: status)
        }
    }

    private func write(_ devices: [TrustedBridgeDevice]) throws {
        let data = try encoder.encode(devices)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: account,
            kSecAttrService as String: service,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]

        var status = SecItemAdd(query as CFDictionary, nil)
        if status == errSecDuplicateItem {
            let updateQuery: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrAccount as String: account,
                kSecAttrService as String: service
            ]
            let updateAttrs: [String: Any] = [
                kSecValueData as String: data
            ]
            status = SecItemUpdate(updateQuery as CFDictionary, updateAttrs as CFDictionary)
        }

        guard status == errSecSuccess else {
            throw KeychainManager.KeychainError.unhandledError(status: status)
        }
    }

    private func readData() throws -> Data {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: account,
            kSecAttrService as String: service,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var out: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &out)
        guard status == errSecSuccess else {
            if status == errSecItemNotFound {
                throw KeychainManager.KeychainError.itemNotFound
            }
            throw KeychainManager.KeychainError.unhandledError(status: status)
        }
        guard let data = out as? Data else {
            throw KeychainManager.KeychainError.unexpectedData
        }
        return data
    }
}
