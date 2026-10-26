//
//  KeychainCredentialStore.swift
//  GlucoseBar
//

import Foundation
import OSLog
import Security

/// Keychain-backed storage for provider credentials.
///
/// Items are generic passwords with `service` set to the bundle identifier and
/// `account` set to `"<sourceUUID>.<field>"`, mirroring the namespaced
/// `UserDefaults` keys they replace.
///
/// Three details are load-bearing:
///
/// * **Reads ask for both classes** (`kSecAttrSynchronizableAny`). An item written
///   as synchronizable is *not* returned by a query that asks only for
///   non-synchronizable items, so a query that named its class would silently stop
///   finding credentials if the iCloud Keychain toggle were ever flipped.
/// * **Writes name their class** and then remove the other copy, so each
///   (source, field) has exactly one item and the storage class never depends on
///   what an earlier version happened to write.
/// * **`kSecUseDataProtectionKeychain` is attempted, not probed.** See
///   `run(_:)`.
struct KeychainCredentialStore: CredentialStoring {

    /// Overridable so the integration test can use a scratch service name instead
    /// of touching the app's real items.
    let service: String

    init(service: String = "t1d.tools.GlucoseBar") {
        self.service = service
    }

    private var logger: Logger {
        Logger(subsystem: "tools.t1d.GlucoseBar", category: "credentials")
    }

    // MARK: - CredentialStoring

    func secret(for field: CredentialField, sourceId: UUID) throws -> String? {
        var result: CFTypeRef?

        let status = try run { useDataProtection in
            var query = baseQuery(field, sourceId, synchronizable: kSecAttrSynchronizableAny, useDataProtection: useDataProtection)
            query[kSecMatchLimit] = kSecMatchLimitOne
            query[kSecReturnData] = true
            return SecItemCopyMatching(query as CFDictionary, &result)
        }

        switch status {
        case errSecSuccess:
            guard let data = result as? Data, let secret = String(data: data, encoding: .utf8) else {
                throw CredentialStoreError.keychain(status: status)
            }
            return secret
        case errSecItemNotFound:
            return nil
        default:
            throw CredentialStoreError.keychain(status: status)
        }
    }

    func setSecret(_ secret: String, for field: CredentialField, sourceId: UUID) throws {
        try write(secret, for: field, sourceId: sourceId, mode: CredentialSyncPreference.mode)
    }

    func deleteSecret(for field: CredentialField, sourceId: UUID) throws {
        try delete(field, sourceId: sourceId, synchronizable: false)
        try delete(field, sourceId: sourceId, synchronizable: true)
    }

    func deleteAll(for sourceId: UUID) throws {
        for field in CredentialField.allCases {
            try deleteSecret(for: field, sourceId: sourceId)
        }
    }

    func deleteAllSecrets() throws {
        for synchronizable in [false, true] {
            let status = try run { useDataProtection in
                let query: [CFString: Any] = [
                    kSecClass: kSecClassGenericPassword,
                    kSecAttrService: service,
                    kSecAttrSynchronizable: synchronizable,
                    kSecUseDataProtectionKeychain: useDataProtection,
                ]
                return SecItemDelete(query as CFDictionary)
            }
            guard status == errSecSuccess || status == errSecItemNotFound else {
                throw CredentialStoreError.keychain(status: status)
            }
        }
    }

    func migrateSecrets(for sourceId: UUID, to mode: CredentialSyncMode) throws {
        for field in CredentialField.allCases {
            // Reads accept either class, so this also picks up the copy written
            // before the toggle was flipped.
            guard let existing = try secret(for: field, sourceId: sourceId) else { continue }
            try write(existing, for: field, sourceId: sourceId, mode: mode)
        }
    }

    // MARK: - Internals

    /// Runs a keychain operation, retrying once against the legacy keychain when
    /// macOS reports that the data-protection entitlement is missing.
    ///
    /// The data-protection keychain is preferred because it is what makes
    /// `kSecAttrAccessible` meaningful on macOS (the header: *"Set to
    /// kCFBooleanTrue to use kSecAttrAccessGroup and/or kSecAttrAccessible on macOS
    /// without requiring the item to be marked synchronizable"*). Ad-hoc and
    /// unsigned builds — including the unit-test host — cannot use it and get
    /// `errSecMissingEntitlement` (-34018).
    ///
    /// Deliberately *not* probed up front: a probe reads an item that does not
    /// exist, gets `errSecItemNotFound`, and never reports the missing entitlement,
    /// so it concludes the wrong thing. This way the answer comes from a real
    /// operation, and the fallback is remembered after the first one.
    private func run(_ operation: (_ useDataProtection: Bool) throws -> OSStatus) throws -> OSStatus {
        let preferred = Backend.shared.useDataProtectionKeychain
        let status = try operation(preferred)

        guard status == errSecMissingEntitlement, preferred else { return status }

        Backend.shared.fallBackToLegacyKeychain(logger: logger)
        return try operation(false)
    }

    private func account(_ field: CredentialField, _ sourceId: UUID) -> String {
        "\(sourceId.uuidString).\(field.rawValue)"
    }

    private func baseQuery(
        _ field: CredentialField,
        _ sourceId: UUID,
        synchronizable: Any,
        useDataProtection: Bool
    ) -> [CFString: Any] {
        [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account(field, sourceId),
            kSecAttrSynchronizable: synchronizable,
            kSecUseDataProtectionKeychain: useDataProtection,
        ]
    }

    /// Adds or updates the item in `mode`, then removes any copy left in the other
    /// class.
    ///
    /// The order matters: the new value is committed *before* anything is removed,
    /// so a failure can only leave a stale duplicate — which reads accept, because
    /// they ask for both classes — never a lost credential.
    private func write(_ secret: String, for field: CredentialField, sourceId: UUID, mode: CredentialSyncMode) throws {
        let data = Data(secret.utf8)

        let status = try run { useDataProtection in
            let updateQuery = baseQuery(field, sourceId, synchronizable: mode.isSynchronizable, useDataProtection: useDataProtection)
            let attributes: [CFString: Any] = [
                kSecValueData: data,
                kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlock,
            ]

            let updateStatus = SecItemUpdate(updateQuery as CFDictionary, attributes as CFDictionary)
            guard updateStatus == errSecItemNotFound else { return updateStatus }

            var addQuery = updateQuery
            addQuery[kSecValueData] = data
            addQuery[kSecAttrAccessible] = kSecAttrAccessibleAfterFirstUnlock
            return SecItemAdd(addQuery as CFDictionary, nil)
        }

        guard status == errSecSuccess else {
            throw CredentialStoreError.keychain(status: status)
        }

        // Remove any copy left in the other class — but only where the two classes
        // are actually distinct.
        //
        // The legacy keychain has a single item space and ignores the synchronizable
        // attribute when matching: a delete carrying `kSecAttrSynchronizable: true`
        // matches (and deletes) an item that was added as non-synchronizable. Doing
        // this cleanup there would delete the item that was just written, which made
        // every save silently vanish. Verified against the real keychain — see
        // `KeychainStoreIntegrationTests.testRoundTripAndUpdate`.
        guard Backend.shared.useDataProtectionKeychain else { return }

        // Best-effort: a failure here leaves a duplicate rather than breaking the
        // credential, so it is logged, not thrown.
        do {
            try delete(field, sourceId: sourceId, synchronizable: !mode.isSynchronizable)
        } catch {
            logger.dlog("Could not remove the stale \(field.rawValue) entry: \(error)", category: "credentials", level: .error)
        }
    }

    private func delete(_ field: CredentialField, sourceId: UUID, synchronizable: Bool) throws {
        let status = try run { useDataProtection in
            let query = baseQuery(field, sourceId, synchronizable: synchronizable, useDataProtection: useDataProtection)
            return SecItemDelete(query as CFDictionary)
        }
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw CredentialStoreError.keychain(status: status)
        }
    }
}

/// Remembers which keychain this process should talk to, so the -34018 fallback is
/// learned once rather than re-tried on every operation.
private final class Backend: @unchecked Sendable {
    static let shared = Backend()

    private let lock = NSLock()
    private var dataProtectionUsable = true

    var useDataProtectionKeychain: Bool {
        lock.lock()
        defer { lock.unlock() }
        return dataProtectionUsable
    }

    func fallBackToLegacyKeychain(logger: Logger) {
        lock.lock()
        let wasUsable = dataProtectionUsable
        dataProtectionUsable = false
        lock.unlock()

        guard wasUsable else { return }
        logger.dlog("Data protection keychain unavailable in this build; using the legacy keychain", category: "credentials", level: .default)
    }
}
