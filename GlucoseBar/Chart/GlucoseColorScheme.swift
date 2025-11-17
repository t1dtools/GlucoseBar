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
            return String(localized: "Static", comment: "The descriptive name for the traditional glucose color scheme of red, green and yellow")
        case .dynamicColor:
            return String(localized: "Dynamic", comment: "The descriptive name for the dynamic glucose color scheme which transitions from purple, through green over to red")
        }
    }
}
