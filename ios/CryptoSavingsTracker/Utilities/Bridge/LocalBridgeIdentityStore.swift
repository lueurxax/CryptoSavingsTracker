import CryptoKit
import Foundation
import Security

struct BridgeSigningIdentitySnapshot: Equatable, Sendable {
    let signingKeyID: String
    let algorithm: String
    let publicKeyRepresentation: String
    let fingerprint: String
}

protocol BridgePackageSigning {
    func identity(for signingKeyID: String) throws -> BridgeSigningIdentitySnapshot
    func sign(_ data: Data, keyID: String) throws -> String
    func verify(signature: String, payload: Data, publicKeyRepresentation: String) throws
}

enum LocalBridgeIdentityStoreError: LocalizedError {
    case missingKey(String)
    case invalidPublicKey
    case invalidSignatureEncoding
    case invalidSignature
    case keychainFailure(OSStatus)

    var errorDescription: String? {
        switch self {
        case .missingKey(let keyID):
            return "No bridge signing key exists for key id \(keyID)."
        case .invalidPublicKey:
            return "The trusted device public key is invalid."
        case .invalidSignatureEncoding:
            return "The signed import package signature could not be decoded."
        case .invalidSignature:
            return "The signed import package signature is invalid."
        case let .keychainFailure(status):
            return "Bridge identity keychain failure (\(status))."
        }
    }
}

final class LocalBridgeIdentityStore: BridgePackageSigning {
    private let service = "com.cryptosavingstracker.bridge.identity"
    private let algorithm = "P256.Signing.ECDSA.SHA256"

    func createTrustedDevice(displayName: String) throws -> TrustedBridgeDevice {
        let keyID = UUID().uuidString
        let identity = try identity(for: keyID)

        return TrustedBridgeDevice(
            id: UUID(),
            displayName: displayName,
            fingerprint: identity.fingerprint,
            signingKeyID: identity.signingKeyID,
            publicKeyRepresentation: identity.publicKeyRepresentation,
            signingAlgorithm: identity.algorithm,
            addedAt: .now,
            lastSuccessfulSyncAt: nil,
            trustState: .active
        )
    }

    func identity(for signingKeyID: String) throws -> BridgeSigningIdentitySnapshot {
        let privateKey = try loadOrCreatePrivateKey(keyID: signingKeyID)
        let publicKeyData = privateKey.publicKey.x963Representation
        return BridgeSigningIdentitySnapshot(
            signingKeyID: signingKeyID,
            algorithm: algorithm,
            publicKeyRepresentation: publicKeyData.base64EncodedString(),
            fingerprint: Self.fingerprint(publicKeyData: publicKeyData)
        )
    }

    func sign(_ data: Data, keyID: String) throws -> String {
        let privateKey = try loadOrCreatePrivateKey(keyID: keyID)
        let signature = try privateKey.signature(for: data)
        return signature.derRepresentation.base64EncodedString()
    }

    func verify(signature: String, payload: Data, publicKeyRepresentation: String) throws {
        guard let publicKeyData = Data(base64Encoded: publicKeyRepresentation) else {
            throw LocalBridgeIdentityStoreError.invalidPublicKey
        }
        guard let signatureData = Data(base64Encoded: signature) else {
            throw LocalBridgeIdentityStoreError.invalidSignatureEncoding
        }
        let publicKey = try P256.Signing.PublicKey(x963Representation: publicKeyData)
        let signatureValue = try P256.Signing.ECDSASignature(derRepresentation: signatureData)
        guard publicKey.isValidSignature(signatureValue, for: payload) else {
            throw LocalBridgeIdentityStoreError.invalidSignature
        }
    }

    func verify(
        _ data: Data,
        signature: String,
        packageKeyID: String,
        trustedDevice: TrustedBridgeDevice?
    ) -> BridgeImportSignatureStatus {
        guard let trustedDevice, trustedDevice.trustState == .active else {
            return .signerUntrusted
        }
        guard trustedDevice.signingKeyID == packageKeyID,
              let publicKeyString = trustedDevice.publicKeyRepresentation,
              let publicKeyData = Data(base64Encoded: publicKeyString) else {
            return .signerUntrusted
        }
        guard let signatureData = Data(base64Encoded: signature),
              let signatureValue = try? P256.Signing.ECDSASignature(derRepresentation: signatureData),
              let publicKey = try? P256.Signing.PublicKey(x963Representation: publicKeyData) else {
            return .invalid
        }
        return publicKey.isValidSignature(signatureValue, for: data) ? .valid : .invalid
    }

    static func fingerprint(publicKeyData: Data) -> String {
        SHA256.hash(data: publicKeyData).map { String(format: "%02X", $0) }.joined()
    }

    private func loadOrCreatePrivateKey(keyID: String) throws -> P256.Signing.PrivateKey {
        if let privateKey = try readPrivateKey(account: keyID) {
            return privateKey
        }

        let privateKey = P256.Signing.PrivateKey()
        try write(privateKey.rawRepresentation, account: keyID)
        return privateKey
    }

    private func loadPrivateKey(keyID: String) throws -> P256.Signing.PrivateKey {
        let data = try read(account: keyID)
        return try P256.Signing.PrivateKey(rawRepresentation: data)
    }

    private func write(_ data: Data, account: String) throws {
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
            throw LocalBridgeIdentityStoreError.keychainFailure(status)
        }
    }

    private func read(account: String) throws -> Data {
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
                throw LocalBridgeIdentityStoreError.missingKey(account)
            }
            throw LocalBridgeIdentityStoreError.keychainFailure(status)
        }
        guard let data = out as? Data else {
            throw KeychainManager.KeychainError.unexpectedData
        }
        return data
    }

    private func readPrivateKey(account: String) throws -> P256.Signing.PrivateKey? {
        do {
            let data = try read(account: account)
            return try P256.Signing.PrivateKey(rawRepresentation: data)
        } catch LocalBridgeIdentityStoreError.missingKey {
            return nil
        }
    }
}
