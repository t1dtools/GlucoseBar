import SwiftUI
import AppKit

/// A `Codable` RGBA wrapper around `SwiftUI.Color` / `NSColor`.
/// Stored as four `Double` components (red, green, blue, alpha).
public struct CodableColor: Codable, Equatable, Hashable, Sendable {
    public var red: Double
    public var green: Double
    public var blue: Double
    public var alpha: Double

    public init(red: Double, green: Double, blue: Double, alpha: Double = 1.0) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    /// Converts a SwiftUI `Color` to a `CodableColor`.
    /// Falls back to white if the color space conversion fails.
    public init(_ color: Color) {
        let ns = NSColor(color).usingColorSpace(.sRGB)
            ?? NSColor(color).usingColorSpace(.deviceRGB)
            ?? NSColor.white
        red   = Double(ns.redComponent)
        green = Double(ns.greenComponent)
        blue  = Double(ns.blueComponent)
        alpha = Double(ns.alphaComponent)
    }

    /// Returns the corresponding SwiftUI `Color`.
    public var color: Color {
        Color(red: red, green: green, blue: blue, opacity: alpha)
    }

    public static let white = CodableColor(red: 1, green: 1, blue: 1)
    public static let black = CodableColor(red: 0, green: 0, blue: 0)
}
