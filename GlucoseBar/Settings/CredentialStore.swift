//
//  CredentialStore.swift
//  GlucoseBar
//

import Foundation

/// The per-source secrets GlucoseBar stores.
///
/// Raw values match the `UserDefaults` key suffixes used before credentials moved
/// to the Keychain, so migrating an existing installation is a straight read of the
/// old key.
enum CredentialField: String, CaseIterable, Sendable {
    case nightscoutToken = "nsSecret"
    case dexcomPassword = "dxPassword"
    case librePassword = "librePassword"
    case tandemPassword = "tandemPassword"

    /// For diagnostics and error messages only — never the value.
    var label: String {
        switch self {
        case .nightscoutToken:
            return String(localized: "Nightscout token", comment: "Name of a stored credential, used in diagnostics and error messages")
        case .dexcomPassword:
            return String(localized: "Dexcom Share password", comment: "Name of a stored credential, used in diagnostics and error messages")
        case .librePassword:
            return String(localized: "LibreLinkUp password", comment: "Name of a stored credential, used in diagnostics and error messages")
        case .tandemPassword:
            return String(localized: "Tandem Source password", comment: "Name of a stored credential, used in diagnostics and error messages")
        }
    }
}

/// Which class a credential is stored in.
///
/// The two classes are separate item spaces: an item written as synchronizable is
/// not returned by a query that asks only for non-synchronizable items and vice
/// versa. Writes therefore always name their class explicitly and clean up the
/// other one, so a given (source, field) has exactly one copy.
enum CredentialSyncMode: Sendable {
    /// This Mac's keychain only.
    case local
    /// This Mac's keychain, plus iCloud Keychain when the user has it enabled.
    case iCloudKeychain

    var isSynchronizable: Bool { self == .iCloudKeychain }
}

enum CredentialStoreError: Error, Equatable {
    /// The keychain returned an unexpected `OSStatus`.
    case keychain(status: Int32)
    /// The in-memory store, simulating a failed write.
    case unavailable
}

/// Persistence for the secrets that used to sit in plaintext `UserDefaults`.
///
/// A protocol because the app runs against the Keychain while tests run against an
/// in-memory implementation: the unit-test host is ad-hoc signed (where the
/// data-protection keychain is unavailable), and tests must never touch the
/// developer's real keychain.
protocol CredentialStoring: Sendable {
    /// Returns the stored secret, or nil when nothing is stored.
    func secret(for field: CredentialField, sourceId: UUID) throws -> String?
    func setSecret(_ secret: String, for field: CredentialField, sourceId: UUID) throws
    func deleteSecret(for field: CredentialField, sourceId: UUID) throws
    /// Removes every credential belonging to one source.
    func deleteAll(for sourceId: UUID) throws
    /// Removes every credential GlucoseBar stores, for every source. Used by the
    /// "reset all data" path, which wipes the settings store wholesale.
    func deleteAllSecrets() throws
    /// Re-stores each of a source's secrets in `mode`, leaving exactly one copy in
    /// one item space. Used when the user flips the iCloud Keychain toggle.
    func migrateSecrets(for sourceId: UUID, to mode: CredentialSyncMode) throws
}

/// In-memory implementation for tests and previews.
final class InMemoryCredentialStore: CredentialStoring, @unchecked Sendable {

    private let lock = NSLock()
    private var storage: [String: String] = [:]

    /// When true, every write throws, so the migration's failure handling can be
    /// tested. Writes are the only thing that can fail.
    var failsWrites = false

    /// The mode the last write went through, so a caller can assert that flipping
    /// the toggle re-stores credentials.
    private(set) var lastWriteMode: CredentialSyncMode?

    private func key(_ field: CredentialField, _ sourceId: UUID) -> String {
        "\(sourceId.uuidString).\(field.rawValue)"
    }

    func secret(for field: CredentialField, sourceId: UUID) throws -> String? {
        lock.lock()
        defer { lock.unlock() }
        return storage[key(field, sourceId)]
    }

    func setSecret(_ secret: String, for field: CredentialField, sourceId: UUID) throws {
        try setSecret(secret, for: field, sourceId: sourceId, mode: .local)
    }

    private func setSecret(_ secret: String, for field: CredentialField, sourceId: UUID, mode: CredentialSyncMode) throws {
        lock.lock()
        defer { lock.unlock() }
        if failsWrites { throw CredentialStoreError.unavailable }
        storage[key(field, sourceId)] = secret
        lastWriteMode = mode
    }

    func deleteSecret(for field: CredentialField, sourceId: UUID) throws {
        lock.lock()
        defer { lock.unlock() }
        storage.removeValue(forKey: key(field, sourceId))
    }

    func deleteAll(for sourceId: UUID) throws {
        lock.lock()
        defer { lock.unlock() }
        let prefix = "\(sourceId.uuidString)."
        storage = storage.filter { !$0.key.hasPrefix(prefix) }
    }

    func deleteAllSecrets() throws {
        lock.lock()
        defer { lock.unlock() }
        storage.removeAll()
    }

    func migrateSecrets(for sourceId: UUID, to mode: CredentialSyncMode) throws {
        // Storage is class-agnostic in memory, but re-write through the mode so a
        // test can assert the migration ran.
        lock.lock()
        let prefix = "\(sourceId.uuidString)."
        let entries = storage.filter { $0.key.hasPrefix(prefix) }
        lock.unlock()

        for (storedKey, value) in entries {
            guard let field = CredentialField.allCases.first(where: { key($0, sourceId) == storedKey }) else { continue }
            try setSecret(value, for: field, sourceId: sourceId, mode: mode)
        }
    }
}

/// Whether credentials should also be stored in iCloud Keychain.
///
/// A global setting, like debug mode, rather than per-source: it describes what
/// happens to every source's credentials. Defaults to off, and is read on each
/// write so flipping it takes effect without rebuilding the store.
enum CredentialSyncPreference {
    static let defaultsKey = "credentialSyncToICloudKeychain"

    static var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: defaultsKey)
    }

    static var mode: CredentialSyncMode {
        isEnabled ? .iCloudKeychain : .local
    }
}
