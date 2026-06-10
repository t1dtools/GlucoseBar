import Foundation

// Make CGMProvider usable as a Codable field.
// String-backed enums get automatic Codable synthesis when conformance is declared.
extension CGMProvider: Codable {}

/// Minimal `Codable` value type representing a CGM source's identity.
/// Used during migration and source-list persistence.
struct SourceConfiguration: Identifiable, Codable {
    var id: UUID
    var sourceName: String
    var iconSymbol: String       // SF Symbol name, e.g. "person.fill"
    var iconColor: CodableColor
    var providerType: CGMProvider
    var isEnabled: Bool

    init(
        id: UUID = UUID(),
        sourceName: String = "My CGM",
        iconSymbol: String = "person.fill",
        iconColor: CodableColor = .white,
        providerType: CGMProvider = .null,
        isEnabled: Bool = true
    ) {
        self.id = id
        self.sourceName = sourceName
        self.iconSymbol = iconSymbol
        self.iconColor = iconColor
        self.providerType = providerType
        self.isEnabled = isEnabled
    }
}
