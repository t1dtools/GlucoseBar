// Imported directly from Trio, minimal modifications only.

import Foundation
import SwiftUI

public enum GlucoseColorScheme: String, CaseIterable, Identifiable, Codable, Hashable {
    public var id: String { rawValue }
    case staticColor
    case dynamicColor

    var displayName: String {
        switch self {
        case .staticColor:
            return String(localized: "Static")
        case .dynamicColor:
            return String(localized: "Dynamic")
        }
    }
}
